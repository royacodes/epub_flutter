import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:epub_flutter/src/data/epub_cfi_reader.dart';
import 'package:epub_flutter/src/data/epub_parser.dart';
import 'package:epub_flutter/src/data/models/chapter.dart';
import 'package:epub_flutter/src/data/models/chapter_view_value.dart';
import 'package:epub_flutter/src/data/models/paragraph.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:html_unescape/html_unescape.dart';
import 'package:page_flip/page_flip.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../data/models/page_model.dart';

export 'package:epubx/epubx.dart' hide Image;

part '../epub_controller.dart';

part '../utils/epub_view_builders.dart';

const _minTrailingEdge = 0.55;
const _minLeadingEdge = -0.05;

typedef ExternalLinkPressed = void Function(String href);

class EpubView extends StatefulWidget {
  const EpubView({
    required this.controller,
    this.onExternalLinkPressed,
    this.onChapterChanged,
    this.onDocumentLoaded,
    this.onDocumentError,
    this.builders = const EpubViewBuilders<DefaultBuilderOptions>(
      options: DefaultBuilderOptions(),
    ),
    this.shrinkWrap = false,
    Key? key,
  }) : super(key: key);

  final EpubController controller;
  final ExternalLinkPressed? onExternalLinkPressed;
  final bool shrinkWrap;
  final void Function(EpubChapterViewValue? value)? onChapterChanged;

  /// Called when a document is loaded
  final void Function(EpubBook document)? onDocumentLoaded;

  /// Called when a document loading error
  final void Function(Exception? error)? onDocumentError;

  /// Builders
  final EpubViewBuilders builders;

  @override
  State<EpubView> createState() => _EpubViewState();
}

class _EpubViewState extends State<EpubView> {
  Exception? _loadingError;
  ItemScrollController? _itemScrollController;
  ItemPositionsListener? _itemPositionListener;
  List<EpubChapter> _chapters = [];
  List<Paragraph> _paragraphs = [];

  // List<Line> _lines = [];
  List<PageModel> _pages = [];
  EpubCfiReader? _epubCfiReader;
  EpubChapterViewValue? _currentValue;
  final _chapterIndexes = <int>[];

  EpubController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _itemScrollController = ItemScrollController();
    _itemPositionListener = ItemPositionsListener.create();
    _controller._attach(this);
    _controller.loadingState.addListener(() {
      switch (_controller.loadingState.value) {
        case EpubViewLoadingState.loading:
          break;
        case EpubViewLoadingState.success:
          widget.onDocumentLoaded?.call(_controller._document!);
          break;
        case EpubViewLoadingState.error:
          widget.onDocumentError?.call(_loadingError);
          break;
      }

      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _itemPositionListener!.itemPositions.removeListener(_changeListener);
    _controller._detach();
    super.dispose();
  }

  Future<bool> _init() async {
    if (_controller.isBookLoaded.value) {
      return true;
    }
    _chapters = parseChapters(_controller._document!);
    final parseParagraphsResult =
        parseParagraphs(_chapters, _controller._document!.Content);
    _paragraphs = parseParagraphsResult.flatParagraphs;
    final parsePageResult = parsePages(
        _chapters, _controller._document!.Content, recalculateWordsPerPage());
    _pages = parsePageResult.pages;
    _chapterIndexes.addAll(parsePageResult.chapterIndexes);

    _epubCfiReader = EpubCfiReader.parser(
      cfiInput: _controller.epubCfi,
      chapters: _chapters,
      paragraphs: _paragraphs,
    );
    _itemPositionListener!.itemPositions.addListener(_changeListener);
    _controller.isBookLoaded.value = true;

    return true;
  }

  void _changeListener() {
    if (_paragraphs.isEmpty ||
        _itemPositionListener!.itemPositions.value.isEmpty) {
      return;
    }
    final position = _itemPositionListener!.itemPositions.value.first;
    final chapterIndex = _getChapterIndexBy(
      positionIndex: position.index,
      trailingEdge: position.itemTrailingEdge,
      leadingEdge: position.itemLeadingEdge,
    );
    final paragraphIndex = _getParagraphIndexBy(
      positionIndex: position.index,
      trailingEdge: position.itemTrailingEdge,
      leadingEdge: position.itemLeadingEdge,
    );
    _currentValue = EpubChapterViewValue(
      chapter: chapterIndex >= 0 ? _chapters[chapterIndex] : null,
      chapterNumber: chapterIndex + 1,
      paragraphNumber: paragraphIndex + 1,
      position: position,
    );
    _controller.currentValueListenable.value = _currentValue;
    widget.onChapterChanged?.call(_currentValue);
  }

  void _gotoEpubCfi(
    String? epubCfi, {
    double alignment = 0,
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.linear,
  }) {
    _epubCfiReader?.epubCfi = epubCfi;
    final index = _epubCfiReader?.paragraphIndexByCfiFragment;

    if (index == null) {
      return;
    }

    _itemScrollController?.scrollTo(
      index: index,
      duration: duration,
      alignment: alignment,
      curve: curve,
    );
  }

  void _onLinkPressed(String href) {
    if (href.contains('://')) {
      widget.onExternalLinkPressed?.call(href);
      return;
    }

    // Chapter01.xhtml#ph1_1 -> [ph1_1, Chapter01.xhtml] || [ph1_1]
    String? hrefIdRef;
    String? hrefFileName;

    if (href.contains('#')) {
      final dividedHref = href.split('#');
      if (dividedHref.length == 1) {
        hrefIdRef = href;
      } else {
        hrefFileName = dividedHref[0];
        hrefIdRef = dividedHref[1];
      }
    } else {
      hrefFileName = href;
    }

    if (hrefIdRef == null) {
      final chapter = _chapterByFileName(hrefFileName);
      if (chapter != null) {
        final cfi = _epubCfiReader?.generateCfiChapter(
          book: _controller._document,
          chapter: chapter,
          additional: ['/4/2'],
        );

        _gotoEpubCfi(cfi);
      }
      return;
    } else {
      final paragraph = _paragraphByIdRef(hrefIdRef);
      final chapter =
          paragraph != null ? _chapters[paragraph.chapterIndex] : null;

      if (chapter != null && paragraph != null) {
        final paragraphIndex =
            _epubCfiReader?.getParagraphIndexByElement(paragraph.element);
        final cfi = _epubCfiReader?.generateCfi(
          book: _controller._document,
          chapter: chapter,
          paragraphIndex: paragraphIndex,
        );

        _gotoEpubCfi(cfi);
      }

      return;
    }
  }

  Paragraph? _paragraphByIdRef(String idRef) =>
      _paragraphs.firstWhereOrNull((paragraph) {
        if (paragraph.element.id == idRef) {
          return true;
        }

        return paragraph.element.children.isNotEmpty &&
            paragraph.element.children[0].id == idRef;
      });

  EpubChapter? _chapterByFileName(String? fileName) =>
      _chapters.firstWhereOrNull((chapter) {
        if (fileName != null) {
          if (chapter.ContentFileName!.contains(fileName)) {
            return true;
          } else {
            return false;
          }
        }
        return false;
      });

  int _getChapterIndexBy({
    required int positionIndex,
    double? trailingEdge,
    double? leadingEdge,
  }) {
    final posIndex = _getAbsParagraphIndexBy(
      positionIndex: positionIndex,
      trailingEdge: trailingEdge,
      leadingEdge: leadingEdge,
    );
    final index = posIndex >= _chapterIndexes.last
        ? _chapterIndexes.length
        : _chapterIndexes.indexWhere((chapterIndex) {
            if (posIndex < chapterIndex) {
              return true;
            }
            return false;
          });

    return index - 1;
  }

  int _getParagraphIndexBy({
    required int positionIndex,
    double? trailingEdge,
    double? leadingEdge,
  }) {
    final posIndex = _getAbsParagraphIndexBy(
      positionIndex: positionIndex,
      trailingEdge: trailingEdge,
      leadingEdge: leadingEdge,
    );

    final index = _getChapterIndexBy(positionIndex: posIndex);

    if (index == -1) {
      return posIndex;
    }

    return posIndex - _chapterIndexes[index];
  }

  int _getAbsParagraphIndexBy({
    required int positionIndex,
    double? trailingEdge,
    double? leadingEdge,
  }) {
    int posIndex = positionIndex;
    if (trailingEdge != null &&
        leadingEdge != null &&
        trailingEdge < _minTrailingEdge &&
        leadingEdge < _minLeadingEdge) {
      posIndex += 1;
    }

    return posIndex;
  }

  int recalculateWordsPerPage() {
    final defaultBuilder =
        widget.builders as EpubViewBuilders<DefaultBuilderOptions>;
    final options = defaultBuilder.options;
    // Recalculate the number of words per page based on the updated font size
    double screenWidth = MediaQuery.of(context).size.width - (2 * 16);

    // Create a TextPainter to measure the width of a single word
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'words', // Use a sample word
        style: TextStyle(fontSize: options.textStyle.fontSize),
      ),
      textDirection: TextDirection.ltr,
    );

    // Layout the text to calculate its width
    textPainter.layout(maxWidth: screenWidth);

    // Calculate the number of words per line
    double wordsPerLine =
        (screenWidth / (options.textStyle.fontSize! * 2)).floor().toDouble();
    // Calculate the number of lines per page
    double screenHeight = MediaQuery.of(context).size.height - (2 * 16);
    final hw = screenHeight / screenWidth;
    linesPerPage =
        ((screenHeight / (options.textStyle.fontSize! * 2))).floor().toDouble()-5;//5 tedade paragraph
    // linesPerPage = 20;

    // Calculate the number of words per page
    final wordsPerPage = (wordsPerLine * linesPerPage).floor();
    final words = wordsPerPage;
    return words;
  }

  static Widget _chapterDividerBuilder(EpubChapter chapter) => Container(
        height: 56,
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Color(0x24000000),
        ),
        alignment: Alignment.centerLeft,
        child: Text(
          chapter.Title ?? '',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  static Widget _chapterBuilder(
    BuildContext context,
    EpubViewBuilders builders,
    EpubBook document,
    List<EpubChapter> chapters,
    List<Paragraph> paragraphs,
    List<PageModel> pages,
    int index,
    int chapterIndex,
    int paragraphIndex,
    ExternalLinkPressed onExternalLinkPressed,
  ) {
    if (paragraphs.isEmpty) {
      return Container();
    }
    if (pages.isEmpty) {
      return Container();
    }
    String htmlData = '';
    var unescape = HtmlUnescape();
    RegExp exp = RegExp(r"<[^>]*>", multiLine: true, caseSensitive: true);

    for (int i = 0; i < pages[index].elements.length; i++) {
      htmlData =
          '$htmlData\n${pages[index].elements[i].outerHtml.replaceAll(exp, '')}';
    }
    final defaultBuilder = builders as EpubViewBuilders<DefaultBuilderOptions>;
    final options = defaultBuilder.options;
    // return HtmlWidget(lines[index].lineString);
    return SingleChildScrollView(
      child: Container(
        color: options.backgroundColor,
        margin: const EdgeInsetsDirectional.all(16),
        child: SelectableText(
                  htmlData,
                  textAlign: TextAlign.justify,
                  textDirection: TextDirection.ltr,
                  style:
          TextStyle(fontSize: options.textStyle.fontSize, height: 1.5, color: Colors.black,),
          onSelectionChanged: (TextSelection selection, SelectionChangedCause? cause) {

          },
          contextMenuBuilder: ( BuildContext context,
              EditableTextState editableTextState) {
                    return AdaptiveTextSelectionToolbar(
                      anchors: editableTextState.contextMenuAnchors,
                      children: [
                      Container(width: 200,
                      padding: const EdgeInsetsDirectional.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Container(
                            height: 40,
                            width: 40,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.pink,
                            ),
                          ),
                          Container(
                            height: 40,
                            width: 40,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.blue,
                            ),
                          ),
                          Container(
                            height: 40,
                            width: 40,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.green,
                            ),
                          ),
                          Container(
                            height: 40,
                            width: 40,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.amber,
                            ),
                          ),
                        ],
                      ),),

                    ], );
          },
                ),
      ),
    );
  }

  num linesPerPage = 20;

  num calculateLinesPerPage() {
    final defaultBuilder =
        widget.builders as EpubViewBuilders<DefaultBuilderOptions>;
    final options = defaultBuilder.options;
    linesPerPage =
        (MediaQuery.of(context).size.height / options.textStyle.fontSize!)
            .floor();
    num lines = linesPerPage;
    return linesPerPage;
  }

  Widget _buildLoaded(
    BuildContext context,
  ) {
    num lines = calculateLinesPerPage() ?? 0;
    recalculateWordsPerPage();
    // return ListView.builder(
    return PageFlipWidget(
      // itemCount: _paragraphs.length,
      // shrinkWrap: true,
      // itemBuilder: (BuildContext context, int index) {
      //   return widget.builders.chapterBuilder(
      //     context,
      //     widget.builders,
      //     widget.controller._document!,
      //     _chapters,
      //     _paragraphs,
      //     index,
      //     _getChapterIndexBy(positionIndex: index),
      //     _getParagraphIndexBy(positionIndex: index),
      //     _onLinkPressed,
      //   );
      // },
      isRightSwipe: true,
      children: [
        for (var i = 0; i < _pages.length; i++)
          widget.builders.chapterBuilder(
            context,
            widget.builders,
            widget.controller._document!,
            _chapters,
            _paragraphs,
            _pages,
            i,
            _getChapterIndexBy(positionIndex: i),
            _getParagraphIndexBy(positionIndex: i),
            _onLinkPressed,
          ),
      ],
    );
    // return ScrollablePositionedList.builder(
    //   shrinkWrap: widget.shrinkWrap,
    //   initialScrollIndex: _epubCfiReader!.paragraphIndexByCfiFragment ?? 0,
    //   itemCount: _paragraphs.length,
    //   itemScrollController: _itemScrollController,
    //   itemPositionsListener: _itemPositionListener,
    //   itemBuilder: (BuildContext context, int index) {
    //     return widget.builders.chapterBuilder(
    //       context,
    //       widget.builders,
    //       widget.controller._document!,
    //       _chapters,
    //       _paragraphs,
    //       index,
    //       _getChapterIndexBy(positionIndex: index),
    //       _getParagraphIndexBy(positionIndex: index),
    //       _onLinkPressed,
    //     );
    //   },
    // );
  }

  static Widget _builder(
    BuildContext context,
    EpubViewBuilders builders,
    EpubViewLoadingState state,
    WidgetBuilder loadedBuilder,
    Exception? loadingError,
  ) {
    final Widget content = () {
      switch (state) {
        case EpubViewLoadingState.loading:
          return KeyedSubtree(
            key: const Key('epubx.root.loading'),
            child: builders.loaderBuilder?.call(context) ?? const SizedBox(),
          );
        case EpubViewLoadingState.error:
          return KeyedSubtree(
            key: const Key('epubx.root.error'),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: builders.errorBuilder?.call(context, loadingError!) ??
                  Center(child: Text(loadingError.toString())),
            ),
          );
        case EpubViewLoadingState.success:
          return KeyedSubtree(
            key: const Key('epubx.root.success'),
            child: loadedBuilder(context),
          );
      }
    }();

    final defaultBuilder = builders as EpubViewBuilders<DefaultBuilderOptions>;
    final options = defaultBuilder.options;

    return AnimatedSwitcher(
      duration: options.loaderSwitchDuration,
      transitionBuilder: options.transitionBuilder,
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.builders.builder(
      context,
      widget.builders,
      _controller.loadingState.value,
      _buildLoaded,
      _loadingError,
    );
  }
}
