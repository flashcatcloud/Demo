# CMD: rc.2 → rc.3 包溯源（F5 修复）
# AT: 2026-11-03T07:34:17Z / 2026-11-03T15:34:17+0800

## 1. SHA256
```
rc.2: 7b5fb0601853fda478e0fe42ad2ec34405c8bb430e14318d1306c9947cbeeac0
rc.3: 05f4d978f3e0c3f03aedc7831ee6fb7f10b54d12365a994c3fbb27ea05ca5f3f
```
## 2. 包内差异
```
  Files /tmp/rc3-old/categraf/Chart.yaml and /tmp/rc3-new/categraf/Chart.yaml differ
  Files /tmp/rc3-old/categraf/templates/_config.tpl and /tmp/rc3-new/categraf/templates/_config.tpl differ
```
## 3. 差异内容（只有 apiserver 元标签一行 + version）
```
diff -r /tmp/rc3-old/categraf/Chart.yaml /tmp/rc3-new/categraf/Chart.yaml
17c17
< version: 0.2.2-rc.2
---
> version: 0.2.2-rc.3
diff -r /tmp/rc3-old/categraf/templates/_config.tpl /tmp/rc3-new/categraf/templates/_config.tpl
163c163
<       - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_port_name]
---
>       - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
```
## 4. 关闭 controlPlane 时渲染等价
```
  归一化 diff 行数:        0
```

## 5. 追加：README 版本历史更新后重新打包（最终交付包）
```
打包前 SHA: 05f4d978f3e0c3f03aedc7831ee6fb7f10b54d12365a994c3fbb27ea05ca5f3f
打包后 SHA: 633fd00acec54ba298702cd4f656405f7a7d1e444161f9c214b2158a68d7a00d
差异（应只有 README.md）:
  Files /tmp/rc3-new/categraf/Chart.yaml and assets/categraf-helm/categraf/Chart.yaml differ
  Files /tmp/rc3-new/categraf/README.md and assets/categraf-helm/categraf/README.md differ
渲染等价性（同 values，归一化后 diff 行数）:
         0
```
