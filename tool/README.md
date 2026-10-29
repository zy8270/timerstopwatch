# tool/ — 开发期脚本

| 文件 | 职责 | 影响 |
|------|------|------|
| `gen_tick.dart` | 生成滚轮"咔哒"音效 `android/app/src/main/res/raw/wheel_tick.wav`（28ms 衰减正弦，PCM16/44.1kHz），不联网 | 想换音色改参数后 `dart run tool/gen_tick.dart` 重新生成 |
