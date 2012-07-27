(include "errno.h")
(include "stddef.h")

(progn
  (in-package #:zmq-bindings-grovel)
  
  (constant (+eintr+ "EINTR"))
  (constant (+einval+ "EINVAL"))
  (constant (+emfile+ "EMFILE"))
  (constant (+efault+ "EFAULT"))
  (constant (+enodev+ "ENODEV"))
  (constant (+eagain+ "EAGAIN"))

  (ctype size-t "size_t"))