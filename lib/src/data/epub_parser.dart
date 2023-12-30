import 'package:epub_flutter/src/data/epub_cfi_reader.dart';
import 'package:epub_flutter/src/data/models/line.dart';
import 'package:epub_flutter/src/data/models/page_model.dart';
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
List<List<dom.Element>> splitElementIntoPages(
    List<dom.Element> elements, int targetWordCountPerPage) {
   List<dom.Element> result = [];
  int currentWordCount = 0;
  List<List<dom.Element>> currentPage = [];

  for(int i=0; i<elements.length; i++) {
    List<String> words = elements[i].text.split(RegExp(r'\s+'));
    List<String> actualWords = words.where((word) => word.isNotEmpty).toList();
    if(actualWords.length <= targetWordCountPerPage - currentWordCount) {
      currentWordCount = actualWords.length + currentWordCount;
      result.add(elements[i]);
    } else {
      if(targetWordCountPerPage - currentWordCount == 0) {
        currentWordCount = 0;
        result = [];
        if(i == elements.length - 1) {
          result.add(elements[i]);
          currentPage.add(result);
        } else {
          i--;
        }
      } else {
        List<String> sublist = actualWords.sublist(0, (targetWordCountPerPage - currentWordCount) );
        List<String> secondSublist = actualWords.sublist((targetWordCountPerPage - currentWordCount), actualWords.length );
        String textContent = sublist.join(' ');
        String secondTextContent = secondSublist.join(' ');
        dom.Element paragraphElement = dom.Element.tag('p')..text = textContent;
        dom.Element secondParagraphElement = dom.Element.tag('p')..text = secondTextContent;
        result.add(paragraphElement);
        currentPage.add(result);
        words = secondParagraphElement.text.split(RegExp(r'\s+'));
        actualWords = words.where((word) => word.isNotEmpty).toList();
        result = [];
        currentWordCount = 0;
        elements[i] = secondParagraphElement;
        i--;

      }


    }
  }
return currentPage;
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

ParsePagesResult parsePages(
  List<EpubChapter> chapters,
  EpubContent? content,
    int targetWordCount,
) {
  String? filename = '';
  final List<int> chapterIndexes = [];
  final c = content!;
  final pages = chapters.fold<List<PageModel>>(
    [],
    (acc, next) {
      List<dom.Element> elmList = [];
      List<List<dom.Element>> elementList = [];
      if (filename != next.ContentFileName) {
        filename = next.ContentFileName;
        final document = EpubCfiReader().chapterDocument(next);
        if (document != null) {
          final result = convertDocumentToElements(document);
          elmList = _removeAllDiv(result);
          elementList = splitElementIntoPages(elmList, targetWordCount);

        }
      }

      if (next.Anchor == null) {
        // last element from document index as chapter index

        chapterIndexes.add(acc.length);
        acc.addAll(elementList.map(
            (element) => PageModel(element, chapterIndexes.length - 1)));
        return acc;
      } else {
        final index = elmList.indexWhere(
          (elm) => elm.outerHtml.contains(
            'id="${next.Anchor}"',
          ),
        );
        if (index == -1) {
          chapterIndexes.add(acc.length);
          acc.addAll(elementList.map(
              (element) => PageModel(element, chapterIndexes.length - 1)));
          return acc;
        }

        chapterIndexes.add(index);
        acc.addAll(elementList.map(
            (element) => PageModel(element, chapterIndexes.length - 1)));
        return acc;
      }
    },
  );

  return ParsePagesResult(pages, chapterIndexes);
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

  final List<PageModel> pages;
  final List<int> chapterIndexes;
}
