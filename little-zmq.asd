;;;; little-zmq.asd

(cl:eval-when (:load-toplevel :execute)
  (asdf:operate 'asdf:load-op 'cffi-grovel))

(asdf:defsystem #:little-zmq
  :serial t
  :depends-on (#:cffi)
  :components ((:file "bindings-package")
	       (cffi-grovel:grovel-file "grovel.spec")
	       (:file "bindings")
	       (:file "package")
               (:file "little-zmq")))

