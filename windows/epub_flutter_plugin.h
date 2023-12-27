#ifndef FLUTTER_PLUGIN_EPUB_FLUTTER_PLUGIN_H_
#define FLUTTER_PLUGIN_EPUB_FLUTTER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace epub_flutter {

class EpubFlutterPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  EpubFlutterPlugin();

  virtual ~EpubFlutterPlugin();

  // Disallow copy and assign.
  EpubFlutterPlugin(const EpubFlutterPlugin&) = delete;
  EpubFlutterPlugin& operator=(const EpubFlutterPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace epub_flutter

#endif  // FLUTTER_PLUGIN_EPUB_FLUTTER_PLUGIN_H_
