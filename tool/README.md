# tool/ — 开发期脚本

| 文件 | 职责 | 影响 |
|------|------|------|
| `gen_tick.dart` | 生成滚轮"咔哒"音效 `android/app/src/main/res/raw/wheel_tick.wav`（28ms 衰减正弦，PCM16/44.1kHz），不联网 | 想换音色改参数后 `dart run tool/gen_tick.dart` 重新生成 |

## 图标 PNG 拷贝命令（golden 导出 → android res，Git Bash）

`flutter test --update-goldens test/icon_golden_test.dart` 之后执行（在仓库根目录）：

```bash
for dpi in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  d="${dpi%%:*}"
  for key in lightpurple deeppurple cyan yellow lightblue pink green; do
    cp "test/goldens/icon/launcher-${key}-${d}.png" "android/app/src/main/res/mipmap-${d}/ic_launcher_${key}.png"
  done
  cp "test/goldens/icon/launcher-lightpurple-${d}.png" "android/app/src/main/res/mipmap-${d}/ic_launcher.png"
done
```

键集合 = `AppPalette.name`（lib/models/app_palette.dart）；基础 `ic_launcher.png` 恒取默认配色（lightpurple）那套。
