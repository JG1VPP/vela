VeLA: Lisp Engine using PEG and GC written in D
---

## build

```d
$ dmd -of=lisp gc.d lisp.d
```

## usage

```sh
$ ./lisp
DLANG-PEG-LISP> (+ 1 2)
3
DLANG-PEG-LISP> (+ 1 2 3)
6
DLANG-PEG-LISP>
```
