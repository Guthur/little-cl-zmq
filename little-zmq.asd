;;;; little-zmq.asd

(cl:eval-when (:load-toplevel :execute)
  (asdf:operate 'asdf:load-op 'cffi-grovel))

(asdf:defsystem #:little-zmq
  :depends-on (#:cffi
               #:alexandria)
  :licence "MIT"
  :components ((:module src
                :serial t
                :components ((:file "zmq-bindings-grovel")
                             (cffi-grovel:grovel-file "grovel.spec")
                             (:file "bindings")
                             (:file "context")
                             (:file "socket")
                             (:file "message")
                             (:file "poll")
                             (:file "little-zmq")))))

(asdf:defsystem #:little-zmq.devices
  :depends-on (#:little-zmq)
  :components ((:file "devices/standard-devices")))

(asdf:defsystem #:little-zmq.zguide-examples
  :depends-on (#:bordeaux-threads
               #:little-zmq
               #:cl-ppcre)
  :serial t
  :components ((:file "zguide/chapter-1")
               (:file "zguide/chapter-2")
               (:file "zguide/chapter-3")))

(asdf:defsystem #:little-zmq.tests
  :depends-on (#:bordeaux-threads
               #:little-zmq
               #:flexi-streams)
  :serial t
  :components ((:file "tests/util")
               (:file "tests/perf")))