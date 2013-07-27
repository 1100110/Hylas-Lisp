(in-package :hylas)
(annot:enable-annot-syntax)

@document "Defines special forms and code language functions."

@doc "Please don't look at this code. Just don't. Please forgive me."
(defmacro extract (form (&rest bindings) &rest code)
  (let* ((str (make-string-output-stream))
         (bindings (loop for i from 0 to (1- (length bindings)) collecting
                     `((code (emit-code (nth ,i ,form) code))
                       (,(nth i bindings) (res code))
                       (,(read-from-string
                           (concatenate 'string
                             (symbol-name (nth i bindings)) "-type"))
                         (res-type code)))))
         (len (length bindings)))
    (format str "~{(let* ~A~}~{~S~}" bindings code)
    (dotimes (i len) (write-string ")" str))
    (read-from-string (get-output-stream-string str))))

(defparameter *operators* (make-hash-table :test #'equal))
(defparameter *core* (make-hash-table :test #'equal))

(defmacro defbuiltin (table name &rest code)
  `(setf (gethash ,(format nil "~(~A~)" (symbol-name name)) ,table)
    #'(lambda (form code) ,@code)))

(defmacro defop (name &rest code)
  `(defbuiltin *operators* ,name ,@code))
(defmacro defcore (name &rest code)
  `(defbuiltin *core*,name ,@code))

;; Variables

(defop def
  (let ((sym (symbol-name (nth 0 form))))
    (extract (cdr form) (value)
      (if (lookup sym code)
        (raise form "Symbol '~A' already defined in the present scope." sym)
        (progn
          (var sym (var value-type))
          (append-entry code
            (assign (emit "%~A" sym) (res code value-type))))))))

(defop global)

(defop set)

;; Flow Control

(defop if
  (extract form (test true-branch false-branch)
    (if (not (booleanp test-type))
      (raise form "The type of the test expression to (if) must be i1 (boolean).")
      (if (match true-branch-type false-branch-type)
          ;match
          (append-entry code
            (emit "muh code"))
          ;no match
          (raise form "The types of the true and false branches must match")))))

#|(defop begin
  (with-new-scope
    (extract-list)))|#

;; Mathematics

(defmacro generic-twoarg-op (op)
  `(extract form (first second)
    (if (match first-type second-type)
      (append-entry code
        (assign (res code first-type)
          (emit "~A ~A ~A, ~A ~A" ,op first-type first second-type second)))
      (error "Types must match"))))

(defop add
  (generic-twoarg-op "add"))
(defop fadd
  (generic-twoarg-op "fadd"))
(defop sub
  (generic-twoarg-op "sub"))
(defop fsub
  (generic-twoarg-op "fsub"))
(defop mul
  (generic-twoarg-op "mul"))
(defop fmul
  (generic-twoarg-op "fmul"))
(defop udiv
  (generic-twoarg-op "udiv"))
(defop sdiv
  (generic-twoarg-op "sdiv"))
(defop fdiv
  (generic-twoarg-op "fdiv"))
(defop urem
  (generic-twoarg-op "urem"))
(defop srem
  (generic-twoarg-op "srem"))

#|(defmacro make-math-operations ()
  `(progn
    ,@(loop for operator in '(add fadd sub fsub mul fmul udiv sdiv fdiv urem srem)
      collecting `(defop ,operator
        (generic-twoarg-op ,(symbol-name operator))))))
(make-math-operations)|#


;; Bitwise Operations

(defop shl
  (generic-twoarg-op "shl"))
(defop lshr
  (generic-twoarg-op "lshr"))
(defop ashr
  (generic-twoarg-op "ashr"))
(defop bit-and
  (generic-twoarg-op "and"))
(defop bit-or
  (generic-twoarg-op "or"))
(defop bit-xor
  (generic-twoarg-op "xor"))

(defop byte-swap)
(defop count-leading-ones)
(defop count-trailing-ones)
(defop truncate)
(defop extend)
(defop sextend)
(defop zextend)

;; Conversion

(defop ptr->int)
(defop int->ptr)
(defop bitcast)
(defop coerce)

;; Bitfield size

(defop size)
(defop actual-size)

;; Data structures

(defop structure)

(defop struct-nth)
(defop struct-access)

(defop make-array)
(defop global-array)
(defop nth-array)

;; Memory

(defop mem-allocate)
(defop mem-store)
(defop mem-load)

(defop create)
(defop reallocate)
(defop destroy)

(defop address)

;; FFI

(defop link)
(defop foreign)

;; LLVM and Assembler

(defop asm)
(defop inline-asm)
(defop LLVM)
(defop inline-LLVM)

(defparameter initial-code
  (make-instance '<code>
   :operators *operators*
   :core *core*))
