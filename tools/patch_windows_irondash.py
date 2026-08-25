#!/usr/bin/env python3
"""Windows FFI abort 临时规避：irondash 0.1.1/Dart 3.13 在 Windows 启动即 abort。

仅屏蔽 Windows 生成器中的 irondash+super_native 注册，不影响 Android/iOS/Linux/macOS。
幂等：重复运行不会产生双重注释；每次 pub get 后自动重跑。
当 super_clipboard 升级到 0.9+（irondash 0.5+）后可移除本脚本。
"""
from pathlib import Path

project = Path(__file__).resolve().parents[1]
reg = project / "windows/flutter/generated_plugin_registrant.cc"
cmake = project / "windows/flutter/generated_plugins.cmake"
changed = False

if reg.exists():
    raw = reg.read_text(encoding="utf-8")
    # 若已 patch 过，先还原再重 patch，保证幂等不叠注释
    raw = raw.replace(
        "// Disabled Windows FFI abort: irondash 0.1.1/Dart 3.13\n// #include <irondash_engine_context/irondash_engine_context_plugin_c_api.h>",
        "#include <irondash_engine_context/irondash_engine_context_plugin_c_api.h>",
    )
    raw = raw.replace(
        "// #include <super_native_extensions/super_native_extensions_plugin_c_api.h>",
        "#include <super_native_extensions/super_native_extensions_plugin_c_api.h>",
    )
    raw = raw.replace(
        "  // Disabled: IrondashEngineContextPluginCApiRegisterWithRegistrar(\n  //     registry->GetRegistrarForPlugin(\"IrondashEngineContextPluginCApi\"));",
        "  IrondashEngineContextPluginCApiRegisterWithRegistrar(\n      registry->GetRegistrarForPlugin(\"IrondashEngineContextPluginCApi\"));",
    )
    raw = raw.replace(
        "  // SuperNativeExtensionsPluginCApiRegisterWithRegistrar(\n  //     registry->GetRegistrarForPlugin(\"SuperNativeExtensionsPluginCApi\"));",
        "  SuperNativeExtensionsPluginCApiRegisterWithRegistrar(\n      registry->GetRegistrarForPlugin(\"SuperNativeExtensionsPluginCApi\"));",
    )

    t = raw
    if "#include <irondash_engine_context/irondash_engine_context_plugin_c_api.h>" in t:
        t = t.replace(
            "#include <irondash_engine_context/irondash_engine_context_plugin_c_api.h>",
            "// Disabled Windows FFI abort: irondash 0.1.1/Dart 3.13\n// #include <irondash_engine_context/irondash_engine_context_plugin_c_api.h>",
        )
    if "#include <super_native_extensions/super_native_extensions_plugin_c_api.h>" in t:
        t = t.replace(
            "#include <super_native_extensions/super_native_extensions_plugin_c_api.h>",
            "// #include <super_native_extensions/super_native_extensions_plugin_c_api.h>",
        )
    if "  IrondashEngineContextPluginCApiRegisterWithRegistrar(" in t:
        t = t.replace(
            "  IrondashEngineContextPluginCApiRegisterWithRegistrar(\n      registry->GetRegistrarForPlugin(\"IrondashEngineContextPluginCApi\"));",
            "  // Disabled: IrondashEngineContextPluginCApiRegisterWithRegistrar(\n  //     registry->GetRegistrarForPlugin(\"IrondashEngineContextPluginCApi\"));",
        )
    if "  SuperNativeExtensionsPluginCApiRegisterWithRegistrar(" in t:
        t = t.replace(
            "  SuperNativeExtensionsPluginCApiRegisterWithRegistrar(\n      registry->GetRegistrarForPlugin(\"SuperNativeExtensionsPluginCApi\"));",
            "  // SuperNativeExtensionsPluginCApiRegisterWithRegistrar(\n  //     registry->GetRegistrarForPlugin(\"SuperNativeExtensionsPluginCApi\"));",
        )
    if t != raw:
        reg.write_text(t, encoding="utf-8")
        print(f"patched {reg}")
        changed = True
    else:
        # 幂等：已是 patch 态无需重写
        pass

if cmake.exists():
    raw2 = cmake.read_text(encoding="utf-8")
    # 先还原
    raw2 = raw2.replace("  # irondash_engine_context  # disabled Windows FFI abort\n", "  irondash_engine_context\n")
    raw2 = raw2.replace("  # super_native_extensions  # disabled Windows FFI abort\n", "  super_native_extensions\n")
    t = raw2
    for name in ["  irondash_engine_context\n", "  super_native_extensions\n"]:
        if name in t:
            t = t.replace(name, f"  # {name.strip()}  # disabled Windows FFI abort\n")
    if t != raw2:
        cmake.write_text(t, encoding="utf-8")
        print(f"patched {cmake}")
        changed = True

# 未变更也视为成功（幂等）
import sys
sys.exit(0)
