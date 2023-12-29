import 'package:html/dom.dart' as dom;

class Page {
  Page(this.elements, this.chapterIndex);
  final List<dom.Element> elements;
  final int chapterIndex;
}
