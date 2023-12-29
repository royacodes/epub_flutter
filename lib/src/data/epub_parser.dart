import 'package:epub_flutter/src/data/epub_cfi_reader.dart';
import 'package:epub_flutter/src/data/models/line.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import 'models/paragraph.dart';

export 'package:epubx/epubx.dart' hide Image;

List<EpubChapter> parseChapters(EpubBook epubBook) =>
    epubBook.Chapters!.fold<List<EpubChapter>>(
      [],
      (acc, next) {
        acc.add(next);
        next.SubChapters!.forEach(acc.add);
        return acc;
      },
    );

List<dom.Element> convertDocumentToElements(dom.Document document) {
  final doc = document.getElementsByTagName('body').first.children;
  return doc;
}

List<dom.Element> _removeAllDiv(List<dom.Element> elements) {
  final List<dom.Element> result = [];

  for (final node in elements) {
    if (node.localName == 'div' && node.children.length > 1) {
      result.addAll(_removeAllDiv(node.children));
    } else {
      result.add(node);
    }
  }

  return result;
}
List<dom.Element> splitElementIntoPages(
    List<dom.Element> elements, int targetWordCountPerPage) {
  final List<dom.Element> result = [];
  int currentWordCount = 0;
  List<dom.Element> currentPage = [];

  for(var element in elements) {
    List<String> words = element.text.split(RegExp(r'\s+'));
    List<String> actualWords = words.where((word) => word.isNotEmpty).toList();
    if(actualWords.length <= targetWordCountPerPage - currentWordCount) {
      currentWordCount = actualWords.length + currentWordCount;
      result.add(element);
    } else {
      break;
    }
  }
return result;



}

// ParsePagesResult parsePages(
//     List<EpubChapter> chapters,
//     ) {
//   final List<int> chapterIndexes = [];
//   String? filename = '';
//
//   final pages = chapters.fold<List<Page>>(
//       [],
//           (previousValue, element) {
//             List<dom.Element> elmList = [];
//             if(filename != element.ContentFileName) {
//               filename = element.ContentFileName;
//               final document = EpubCfiReader().chapterDocument(element);
//
//
//             }
//
//
//           });
//   return ParsePagesResult(pages, chapterIndexes);
//
//
// }

ParseLinesResult parseLines(
  List<EpubChapter> chapters,
  EpubContent? content,
) {
  String? filename = '';
  final List<int> chapterIndexes = [];
  final c = content!;
  final lines = chapters.fold<List<Line>>(
    [],
    (acc, next) {
      List<dom.Element> elmList = [];
      List<dom.Element> elementList = [];
      if (filename != next.ContentFileName) {
        filename = next.ContentFileName;
        final document = EpubCfiReader().chapterDocument(next);
        if (document != null) {
          final result = convertDocumentToElements(document);
          elmList = _removeAllDiv(result);
          elementList = splitElementIntoPages(elmList, 200);
        }
      }

      if (next.Anchor == null) {
        // last element from document index as chapter index

        chapterIndexes.add(acc.length);
        acc.addAll(elmList.map(
            (element) => Line(element.outerHtml, chapterIndexes.length - 1)));
        return acc;
      } else {
        final index = elmList.indexWhere(
          (elm) => elm.outerHtml.contains(
            'id="${next.Anchor}"',
          ),
        );
        if (index == -1) {
          chapterIndexes.add(acc.length);
          acc.addAll(elmList.map(
              (element) => Line(element.outerHtml, chapterIndexes.length - 1)));
          return acc;
        }

        chapterIndexes.add(index);
        acc.addAll(elmList.map(
            (element) => Line(element.innerHtml, chapterIndexes.length - 1)));
        return acc;
      }
    },
  );

  return ParseLinesResult(lines, chapterIndexes);
}

ParseParagraphsResult parseParagraphs(
  List<EpubChapter> chapters,
  EpubContent? content,
) {
  String? filename = '';
  final List<int> chapterIndexes = [];
  final paragraphs = chapters.fold<List<Paragraph>>(
    [],
    (acc, next) {
      List<dom.Element> elmList = [];
      if (filename != next.ContentFileName) {
        filename = next.ContentFileName;
        final document = EpubCfiReader().chapterDocument(next);
        if (document != null) {
          final result = convertDocumentToElements(document);
          elmList = _removeAllDiv(result);
        }
      }

      if (next.Anchor == null) {
        // last element from document index as chapter index
        chapterIndexes.add(acc.length);
        acc.addAll(elmList
            .map((element) => Paragraph(element, chapterIndexes.length - 1)));
        return acc;
      } else {
        final index = elmList.indexWhere(
          (elm) => elm.outerHtml.contains(
            'id="${next.Anchor}"',
          ),
        );
        if (index == -1) {
          chapterIndexes.add(acc.length);
          acc.addAll(elmList
              .map((element) => Paragraph(element, chapterIndexes.length - 1)));
          return acc;
        }

        chapterIndexes.add(index);
        acc.addAll(elmList
            .map((element) => Paragraph(element, chapterIndexes.length - 1)));
        return acc;
      }
    },
  );

  return ParseParagraphsResult(paragraphs, chapterIndexes);
}

class ParseParagraphsResult {
  ParseParagraphsResult(this.flatParagraphs, this.chapterIndexes);

  final List<Paragraph> flatParagraphs;
  final List<int> chapterIndexes;
}

class ParseLinesResult {
  ParseLinesResult(this.lines, this.chapterIndexes);

  final List<Line> lines;
  final List<int> chapterIndexes;
}

class ParsePagesResult {
  ParsePagesResult(this.pages, this.chapterIndexes);

  final List<Page> pages;
  final List<int> chapterIndexes;
}
