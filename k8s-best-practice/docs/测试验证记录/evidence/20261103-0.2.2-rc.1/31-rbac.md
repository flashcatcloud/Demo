# CMD: G4 RBAC can-i 断言
# AT: 2026-11-03T06:25:51Z / 2026-11-03T14:25:51+0800

## operator SA
```
  get nodes                                        yes
  list nodes                                       yes
  get daemonsets.apps -n categraf                  yes
  create leases.coordination.k8s.io -n categraf    yes
  create secrets -n categraf                       no
  list pods -n categraf                            no
```
## node-agent SA
```
  list pods                                        yes
  get nodes/metrics                                yes
  get nodes/stats                                  yes
  get nodes/proxy                                  yes
  list endpointslices.discovery.k8s.io             yes
  get /metrics                                     yes
  create secrets -n categraf                       no
```
