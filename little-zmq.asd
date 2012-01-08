;;;; little-zmq.asd

(cl:eval-when (:load-toplevel :execute)
  (asdf:operate 'asdf:load-op 'cffi-grovel))

(asdf:defsystem #:little-zmq
  :serial t
  :depends-on (#:cffi #:trivial-garbage #:bordeaux-threads)
  :components ((:file "bindings-package")
	       (cffi-grovel:grovel-file "grovel.spec")
	       (:file "bindings")
	       (:file "package")
	       (:file "message")
	       (:file "poll")
               (:file "little-zmq")
	       (:file "tests")))

