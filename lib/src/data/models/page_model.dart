import 'package:html/dom.dart' as dom;

class PageModel {
  PageModel(this.elements, this.chapterIndex);
  final List<dom.Element> elements;
  final int chapterIndex;
}
