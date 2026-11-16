# CMD: G9 交付包溯源：运行回归的旧包 vs 当前交付包，证明仅 README 差异
# AT: 2026-11-03T06:52:58Z / 2026-11-03T14:52:58+0800

## 包 SHA256
```
运行回归的包（旧）: 88d9449a809096b60866355e58bdee5a7bb6488a9ff683252adad8b35a238a3a
当前交付包（新）:   abad2980c6f01a75e2533c88c5c7baa1a460c050820de8840a78556c27ddd725
新包大小: 17566 bytes
```
## 解包内容差异（应仅 README.md）
```
diff -r /tmp/repack-old/categraf/README.md /tmp/repack-new/categraf/README.md
```
## 渲染等价性（同 values，Helm template diff 行数）
```
diff 行数 = 0 （0 = 运行时行为一致）
```
## 新包 lint
```

1 chart(s) linted, 0 chart(s) failed
```
## 结论
```
重建只改变 Chart 内 README.md（文档），模板渲染与运行时行为零差异，
因此集群回归结论适用于交付包 abad2980c6f01a75e2533c88c5c7baa1a460c050820de8840a78556c27ddd725。
```
