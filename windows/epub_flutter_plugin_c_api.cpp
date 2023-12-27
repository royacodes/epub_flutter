#include "include/epub_flutter/epub_flutter_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "epub_flutter_plugin.h"

void EpubFlutterPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  epub_flutter::EpubFlutterPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
