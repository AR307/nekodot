# nekodot 官网

纯静态站点：`index.html`、`styles.css`、`main.js` 与 `assets/`，不依赖构建步骤，可直接部署到 GitHub Pages、任意静态托管或 Relay 之外的 CDN。

- 中文写在页面里，英文由 `main.js` 的字典切换；默认跟随浏览器语言，并记住访客的选择。
- 浅色 / 深色跟随系统，可手动切换；产品截图按主题自动换成对应版本。
- 遵循系统的「减少动态效果」：关闭循环动画，演示回放直接显示结果。
- 字体为 Nunito 与 JetBrains Mono（SIL OFL 1.1，见 `assets/fonts/OFL.txt`）；截图来自演示数据。

本地预览需要通过 HTTP 打开（直接双击文件时浏览器会拦截字体预加载）：

```sh
python -m http.server 4390 --directory apps/site
```

然后访问 http://127.0.0.1:4390 。
