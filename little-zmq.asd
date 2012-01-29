;;;; little-zmq.asd

(cl:eval-when (:load-toplevel :execute)
  (asdf:operate 'asdf:load-op 'cffi-grovel))

(asdf:defsystem #:little-zmq
  :serial t
  :depends-on (#:cffi
	       #:alexandria)
  :components ((:file "bindings-package")
	       (cffi-grovel:grovel-file "grovel.spec")
	       (:file "bindings")
	       (:file "package")
	       (:file "misc")
	       (:file "message")
	       (:file "poll")
               (:file "little-zmq")))

(asdf:defsystem #:little-zmq.devices
  :depends-on (#:little-zmq)
  :components ((:file "devices/standard-devices")))

(asdf:defsystem #:little-zmq.zguide-examples
  :depends-on (#:bordeaux-threads #:little-zmq)
  :components ((:file "zguide/package")
	       (:file "zguide/chapter3")))

(asdf:defsystem #:little-zmq.tests
  :depends-on (#:bordeaux-threads
	       #:little-zmq
	       #:flexi-streams)
  :components ((:file "tests/tests")))