;;;; Copyright (c) 2006-2008 Henrik Hjelte
;;;; Copyright (c) 2008 Hans Hübner (marked parts)
;;;; All rights reserved.
;;;; See the file LICENSE for terms of use and distribution.

(in-package :json)

(defvar *json-output* (make-synonym-stream '*standard-output*)
  "The default output stream for encoding operations.")

(define-condition unencodable-value-error (type-error)
  ((context :accessor unencodable-value-error-context :initarg :context))
  (:documentation
   "Signalled when a datum is passed to ENCODE-JSON (or another
encoder function) which actually cannot be encoded.")
  (:default-initargs :expected-type t)
  (:report
   (lambda (condition stream)
     (with-accessors ((datum type-error-datum)
                      (context unencodable-value-error-context))
         condition
       (format stream
               "Value ~S is not of a type which can be encoded~@[ by ~A~]."
               datum context)))))

(defun unencodable-value-error (value &optional context)
  "Signal an UNENCODABLE-VALUE-ERROR."
  (error 'unencodable-value-error :datum value :context context))

(defmacro with-substitute-printed-representation-restart ((object stream)
                                                          &body body)
  "Establish a SUBSTITUTE-PRINTED-REPRESENTATION restart for OBJECT
and execute BODY."
  `(restart-case (progn ,@body)
     (substitute-printed-representation ()
       (let ((repr (with-output-to-string (s)
                     (write ,object :stream s :escape nil)
                     nil)))
         (write-json-string repr ,stream)))))

(defgeneric encode-json (object &optional stream)
  (:documentation "Write a JSON representation of OBJECT to STREAM and
return NIL."))

(defun encode-json-to-string (object)
  "Return the JSON representation of OBJECT as a string."
  (with-output-to-string (stream)
    (encode-json object stream)))

(defmethod encode-json :around (anything &optional (stream *json-output*))
  "If OBJECT is not handled by any specialized encoder signal an error
which the user can correct by choosing to encode the string which is
the printed representation of the OBJECT."
  (with-substitute-printed-representation-restart (anything stream)
    (call-next-method)))

(defmethod encode-json (anything &optional (stream *json-output*))
  "If OBJECT is not handled by any specialized encoder signal an error
which the user can correct by choosing to encode the string which is
the printed representation of the OBJECT."
  (declare (ignore stream))
  (unencodable-value-error anything 'encode-json))

(defmethod encode-json ((nr number) &optional (stream *json-output*))
  "Write the JSON representation of the number NR to STREAM (or to
*JSON-OUTPUT*)."
  (write-json-number nr stream))

(defmethod encode-json ((s string) &optional (stream *json-output*)) 
  "Write the JSON representation of the string S to STREAM (or to
*JSON-OUTPUT*)."
  (write-json-string s stream))

(defmethod encode-json ((c character) &optional (stream *json-output*))
  "JSON does not define a character type, we encode characters as strings."
  (encode-json (string c) stream))

(defmethod encode-json ((s symbol) &optional (stream *json-output*))
  "Write the JSON representation of the symbol S to STREAM (or to
*JSON-OUTPUT*).  If S is boolean, a boolean literal is written.
Otherwise, the name of S is passed to *LISP-IDENTIFIER-NAME-TO-JSON*
and the result is written as string."
  (let ((mapped (car (rassoc s +json-lisp-symbol-tokens+))))
    (if mapped
        (progn (write-string mapped stream) nil)
        (let ((s (funcall *lisp-identifier-name-to-json* (symbol-name s))))
          (write-json-string s stream)))))


;;; The code below is from Hans Hübner's YASON (with modifications).

(defvar *json-aggregate-context* nil
  "NIL outside of any aggregate environment, 'ARRAY or 'OBJECT within
the respective environments.")

(defvar *json-aggregate-first* t
  "T when the first member of a JSON object or array is encoded,
afterward NIL.")

(defun next-aggregate-member (context stream)
  "Between two members of an object or array, print a comma
separator."
  (if (not (eq context *json-aggregate-context*))
      (error "Member encoder used ~:[outside any~;in inappropriate~] ~
              aggregate environment"
             *json-aggregate-context*))
  (prog1 *json-aggregate-first*
    (unless *json-aggregate-first*
      (write-char #\, stream))
    (setq *json-aggregate-first* nil)))

(defmacro with-aggregate ((context begin-char end-char
                           &optional (stream '*json-output*))
                          &body body)
  "Run BODY to encode a JSON aggregate type, delimited by BEGIN-CHAR
and END-CHAR."
  `(let ((*json-aggregate-context* ',context)
         (*json-aggregate-first* t))
     (declare (special *json-aggregate-context* *json-aggregate-first*))
     (write-char ,begin-char ,stream)
     (unwind-protect (progn ,@body)
       (write-char ,end-char ,stream))))

(defmacro with-array ((&optional (stream '*json-output*)) &body body)
  "Open a JSON array, run BODY, then close the array.  Inside the BODY,
AS-ARRAY-MEMBER or ENCODE-ARRAY-MEMBER should be called to encode
members of the array."
  `(with-aggregate (array #\[ #\] ,stream) ,@body))

(defmacro as-array-member ((&optional (stream '*json-output*))
                           &body body)
  "BODY should be a program which encodes exactly one JSON datum to
STREAM.  AS-ARRAY-MEMBER ensures that the datum is properly formatted
as an array member, i. e. separated by comma from any preceding or
following member."
  `(progn
     (next-aggregate-member 'array ,stream)
     ,@body))

(defun encode-array-member (object &optional (stream *json-output*))
  "Encode OBJECT as the next member of the innermost JSON array opened
with WITH-ARRAY in the dynamic context.  OBJECT is encoded using the
ENCODE-JSON generic function, so it must be of a type for which an
ENCODE-JSON method is defined."
  (next-aggregate-member 'array stream)
  (encode-json object stream)
  object)

(defun stream-array-member-encoder (stream
                                    &optional (encoder #'encode-json))
  "Return a function which takes an argument and encodes it to STREAM
as an array member.  The encoding function is taken from the value of
ENCODER (default is #'ENCODE-JSON)."
  (lambda (object)
    (as-array-member (stream)
      (funcall encoder object stream))))

(defmacro with-object ((&optional (stream '*json-output*)) &body body)
  "Open a JSON object, run BODY, then close the object.  Inside the BODY,
AS-OBJECT-MEMBER or ENCODE-OBJECT-MEMBER should be called to encode
members of the object."
  `(with-aggregate (object #\{ #\} ,stream) ,@body))

(defmacro as-object-member ((key &optional (stream '*json-output*))
                             &body body)
  "BODY should be a program which writes exactly one JSON datum to
STREAM.  AS-OBJECT-MEMBER ensures that the datum is properly formatted
as an object member, i. e. preceded by the (encoded) KEY and colon,
and separated by comma from any preceding or following member."
  `(progn
     (next-aggregate-member 'object ,stream)
     (let ((key (encode-json-to-string ,key)))
       (if (char= (aref key 0) #\")
           (progn (write-string key ,stream) nil)
           (encode-json key ,stream)))
     (write-char #\: ,stream)
     ,@body))

(defun encode-object-member (key value
                             &optional (stream *json-output*))
  "Encode KEY and VALUE as a member pair of the innermost JSON object
opened with WITH-OBJECT in the dynamic context.  KEY and VALUE are
encoded using the ENCODE-JSON generic function, so they both must be
of a type for which an ENCODE-JSON method is defined.  If KEY does not
encode to a string, its JSON representation (as a string) is encoded
over again."
  (as-object-member (key stream)
    (encode-json value stream))
  value)

(defun stream-object-member-encoder (stream
                                     &optional (encoder #'encode-json))
  "Return a function which takes two arguments and encodes them to
STREAM as an object member (key:value pair)."
  (lambda (key value)
    (as-object-member (key stream)
      (funcall encoder value stream))))

;;; End of YASON code.


(defmethod encode-json ((s list) &optional (stream *json-output*))
  "Write the JSON representation of the list S to STREAM (or to
*STANDARD-OUTPUT*).  If S is a proper alist, it is encoded as a JSON
object, otherwise as a JSON array."
  (handler-case 
      (write-string (with-output-to-string (temp)
                      (call-next-method s temp))
                    stream)
    (type-error (e)
      (declare (ignore e))
      (encode-json-alist s stream))))

(defmethod encode-json((s sequence) stream)
   (let ((first-element t))
     (write-char #\[ stream)    
     (map nil #'(lambda (element) 
                 (if first-element
                     (setf first-element nil)
                     (write-char #\, stream))
                 (encode-json element stream))
         s)
    (write-char #\] stream)))

(defmacro write-json-object (generator-fn stream)
  (let ((strm (gensym))
        (first-element (gensym)))
    `(let ((,first-element t)
           (,strm ,stream))
      (write-char #\{ ,strm)
      (loop
       (multiple-value-bind (more name value)
           (,generator-fn)
         (unless more (return))
         (if ,first-element
             (setf ,first-element nil)
             (write-char #\, ,strm))
         (encode-json name ,strm)
         (write-char #\: ,strm)
         (encode-json value ,strm)))
      (write-char #\} ,strm))))

(defmethod encode-json ((h hash-table) &optional (stream *json-output*))
  "Write the JSON representation (object) of the hash table H to
STREAM (or to *JSON-OUTPUT*)."
  (with-object (stream)
    (maphash (stream-object-member-encoder stream) h)))

#+cl-json-clos
(defmethod encode-json ((o standard-object)
                        &optional (stream *json-output*))
  "Write the JSON representation (object) of the CLOS object O to
STREAM (or to *JSON-OUTPUT*)."
  (with-object (stream)
    (map-slots (stream-object-member-encoder stream) o)))

(defun encode-json-alist (alist &optional (stream *json-output*))
  "Write the JSON representation (object) of ALIST to STREAM (or to
*JSON-OUTPUT*).  Return NIL."
  (with-substitute-printed-representation-restart (alist stream)
    (write-string
     (with-output-to-string (temp)
       (with-object (temp)
         (loop
           with bindings = alist
           do (if (listp bindings)
                  (if (endp bindings)
                      (return)
                      (let ((binding (pop bindings)))
                        (if (consp binding)
                            (destructuring-bind (key . value) binding
                              (encode-object-member key value temp))
                            (unencodable-value-error
                             alist 'encode-json-alist))))
                  (unencodable-value-error alist 'encode-json-alist)))))
     stream)
    nil))

(defun encode-json-alist-to-string (alist)
  "Return the JSON representation (object) of ALIST as a string."
  (with-output-to-string (stream)
    (encode-json-alist alist stream)))

(defun encode-json-plist (plist &optional (stream *json-output*))
  "Write the JSON representation (object) of PLIST to STREAM (or to
*JSON-OUTPUT*).  Return NIL."
  (with-substitute-printed-representation-restart (plist stream)
    (write-string
     (with-output-to-string (temp)
       (with-object (temp)
         (loop
           with properties = plist
           do (if (listp properties)
                  (if (endp properties)
                      (return)
                      (let ((indicator (pop properties)))
                        (if (and (listp properties)
                                 (not (endp properties)))
                            (encode-object-member
                             indicator (pop properties) temp)
                            (unencodable-value-error
                             plist 'encode-json-plist))))
                  (unencodable-value-error plist 'encode-json-plist)))))
     stream)
    nil))

(defun encode-json-plist-to-string (plist)
  "Return the JSON representation (object) of PLIST as a string."
  (with-output-to-string (stream)
    (encode-json-plist plist stream)))

(defun write-json-string (s stream)
  "Write a JSON string representation of S (double-quote-delimited
string) to STREAM."
  (write-char #\" stream)
  (if (stringp s)
      (write-json-chars s stream)
      (encode-json s stream))
  (write-char #\" stream)
  nil)

(defun write-json-chars (s stream)
  "Write JSON representations (chars or escape sequences) of
characters in string S to STREAM."
  (loop for ch across s
     for code = (char-code ch)
     with special
     if (setq special (car (rassoc ch +json-lisp-escaped-chars+)))
       do (write-char #\\ stream) (write-char special stream)
     else if (< #x1f code #x7f)
       do (write-char ch stream)
     else
       do (let ((special '#.(rassoc-if #'consp +json-lisp-escaped-chars+)))
            (destructuring-bind (esc . (width . radix)) special
              (format stream "\\~C~V,V,'0R" esc radix width code)))))

(defun write-json-number (nr stream)
  "Write the JSON representation of the number NR to STREAM."
  (typecase nr
    (integer (format stream "~d" nr))
    (real (format stream "~f" nr))
    (t (unencodable-value-error nr 'write-json-number))))
