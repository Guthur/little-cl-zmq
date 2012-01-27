;;;; little-zmq.asd

(cl:eval-when (:load-toplevel :execute)
  (asdf:operate 'asdf:load-op 'cffi-grovel))

(asdf:defsystem #:little-zmq
  :serial t
  :depends-on (#:cffi
	       #:trivial-garbage
	       #:bordeaux-threads
	       #:alexandria
	       #:flexi-streams)
  :components ((:file "bindings-package")
	       (cffi-grovel:grovel-file "grovel.spec")
	       (:file "bindings")
	       (:file "package")
	       (:file "misc")
	       (:file "message")
	       (:file "poll")
               (:file "little-zmq")
	       (:file "tests")))

(asdf:defsystem #:zguide-examples
  :serial t
  :depends-on (#:bordeaux-threads #:little-zmq)
  :components ((:file "zguide/package")
	       (:file "zguide/chapter3")))