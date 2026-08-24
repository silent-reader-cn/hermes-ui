#!/usr/bin/env python3
"""Windows FFI abort 临时规避：irondash 0.1.1/Dart 3.13 在 Windows 启动即 abort。
仅注释 Windows 生成器中的 irondash+super_native 注册，不影响 Android/iOS。
当 super_clipboard 升级到 0.9+（irondash 0.5+）后可移除本脚本。"""
from pathlib import Path
import sys

project = Path(__file__).resolve().parents[1]
reg = project / "windows/flutter/generated_plugin_registrant.cc"
cmake = project / "windows/flutter/generated_plugins.cmake"
changed = False

if reg.exists():
    t = reg.read_text(encoding="utf-8")
    orig = t
    if "#include <irondash_engine_context/irondash_engine_context_plugin_c_api.h>" in t:
        t = t.replace("#include <irondash_engine_context/irondash_engine_context_plugin_c_api.h>", "// Disabled Windows FFI abort: irondash 0.1.1/Dart 3.13\n// #include <irondash_engine_context/irondash_engine_context_plugin_c_api.h>")
        changed = True
    if "#include <super_native_extensions/super_native_extensions_plugin_c_api.h>" in t:
        t = t.replace("#include <super_native_extensions/super_native_extensions_plugin_c_api.h>", "// #include <super_native_extensions/super_native_extensions_plugin_c_api.h>")
        changed = True
    if "  IrondashEngineContextPluginCApiRegisterWithRegistrar(" in t:
        t = t.replace("  IrondashEngineContextPluginCApiRegisterWithRegistrar(\n      registry->GetRegistrarForPlugin(\"IrondashEngineContextPluginCApi\"));", "  // Disabled: IrondashEngineContextPluginCApiRegisterWithRegistrar(\n  //     registry->GetRegistrarForPlugin(\"IrondashEngineContextPluginCApi\"));")
        changed = True
    if "  SuperNativeExtensionsPluginCApiRegisterWithRegistrar(" in t:
        t = t.replace("  SuperNativeExtensionsPluginCApiRegisterWithRegistrar(\n      registry->GetRegistrarForPlugin(\"SuperNativeExtensionsPluginCApi\"));", "  // SuperNativeExtensionsPluginCApiRegisterWithRegistrar(\n  //     registry->GetRegistrarForPlugin(\"SuperNativeExtensionsPluginCApi\"));")
        changed = True
    if t != orig:
        reg.write_text(t, encoding="utf-8")
        print(f"patched {reg}")
        changed = True

if cmake.exists():
    t = cmake.read_text(encoding="utf-8")
    orig = t
    for name in ["  irondash_engine_context\n", "  super_native_extensions\n"]:
        if name in t:
            t = t.replace(name, f"  # {name.strip()}  # disabled Windows FFI abort\n")
            changed = True
    if t != orig:
        cmake.write_text(t, encoding="utf-8")
        print(f"patched {cmake}")

sys.exit(0 if changed else 0)
