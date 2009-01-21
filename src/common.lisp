;;;; Copyright (c) 2006-2008 Henrik Hjelte
;;;; All rights reserved.
;;;; See the file LICENSE for terms of use and distribution.

(in-package :json)


;;; Custom variables

(eval-when (:compile-toplevel :load-toplevel)

(defvar *custom-vars* nil)

(defmacro with-shadowed-custom-vars (&body body)
  `(let ,(loop for (var) in *custom-vars*
            collect `(,var (if (boundp ',var) ,var)))
     ,@body))

(defun custom-key-to-variable (key)
  (car (rassoc key *custom-vars*)))

(defmacro loop-on-custom ((key var &optional value) &rest clauses)
  (if value
      (destructuring-bind (key-args . clauses) clauses
        `(loop for (,key ,value) on ,key-args by #'cddr
            for ,var = (custom-key-to-variable ,key)
            if ,var ,@clauses))
      `(loop for (,key . ,var) on *custom-vars*
            ,@clauses)))

(defmacro set-custom-vars (&rest key-args)
  `(setq
    ,@(loop-on-custom (key var value) key-args
         append (list var value))))

(defmacro bind-custom-vars ((&rest key-args) &body body)
  `(let ,(loop-on-custom (key var value) key-args
            collect (list var value))
     ,@body))

)

(defmacro define-custom-var ((key name) &rest other-args)
  `(eval-when (:compile-toplevel :load-toplevel)
     (progn (pushnew '(,name . ,key) *custom-vars* :test #'equal)
            (defvar ,name ,@other-args))))


;;; Characters

(defparameter +json-lisp-escaped-chars+
  '((#\" . #\")
    (#\\ . #\\)
    (#\/ . #\/)
    (#\b . #\Backspace)
    (#\f . #\)
    (#\n . #\Newline)
    (#\r . #\Return)
    (#\t . #\Tab)
    (#\u . (4 . 16)))
  "Mapping between JSON string escape sequences and Lisp chars.")

(defvar *use-strict-json-rules* t
  "If non-nil, signal error on unrecognized escape sequences in JSON
strings.  If nil, translate any such sequence to the char after
slash.")


;;; Symbols

(defparameter *symbol-to-string-fn* #'js::symbol-to-js)

(defvar *json-symbols-package* (find-package 'keyword)
  "The package where json-symbols are interned.
Default KEYWORD, nil = current package.")

(defun json-intern (string)
  "Intern STRING in the current *JSON-SYMBOLS-PACKAGE*."
  (intern string (or *json-symbols-package* *package*)))

(defvar *json-identifier-name-to-lisp* 'camel-case-to-lisp
  "Designator of a function which maps string (name of a JSON object
key) to string (name of a Lisp symbol).")

(defvar *lisp-identifier-name-to-json* 'lisp-to-camel-case
  "Designator of a function which maps string (name of a Lisp symbol)
to string (e. g. name of a JSON object key).")
