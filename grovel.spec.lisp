(include "errno.h")
(include "stddef.h")

(progn
  (in-package #:zmq-bindings)
  
  (constant (+eintr+ "EINTR"))
  (constant (+einval+ "EINVAL"))
  (constant (+emfile+ "EMFILE"))
  (constant (+efault+ "EFAULT"))
  (constant (+enodev+ "ENODEV"))

  (ctype size-t "size_t"))