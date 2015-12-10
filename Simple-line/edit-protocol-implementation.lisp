(cl:in-package #:cluffer-simple-line)

(defmethod cluffer:item-count ((line line))
  (length (contents line)))

(defun make-empty-line ()
  (make-instance 'line
    :cursors '()
    :contents (make-array 0 :fill-pointer t)))
    
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods on ITEMS.

;;; When all the items are asked for, we do not allocate a fresh
;;; vector.  This means that client code is not allowed to mutate the
;;; return value of this function
(defmethod cluffer:items ((line line) &key (start 0) (end nil))
  (if (and (= start 0) (null end))
      (contents line)
      (subseq (contents line) start end)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Detaching and attaching a cursor.

(defmethod cluffer:attach-cursor
    ((cursor attached-cursor) line &optional position)
  (declare (ignore line position))
  (error 'cluffer:cursor-attached))

(defmethod cluffer:attach-cursor
    ((cursor detached-left-sticky-cursor)
     (line line)
     &optional
       (position 0))
  (when (> position (cluffer:item-count line))
    (error 'cluffer:end-of-line))
  (push cursor (cursors line))
  (change-class cursor 'left-sticky-cursor
		:line line
		:cursor-position position)
  nil)

(defmethod cluffer:attach-cursor
    ((cursor detached-right-sticky-cursor)
     (line line)
     &optional
       (position 0))
  (when (> position (cluffer:item-count line))
    (error 'cluffer:end-of-line))
  (push cursor (cursors line))
  (change-class cursor 'right-sticky-cursor
		:line line
		:cursor-position position)
  nil)

(defmethod cluffer:detach-cursor
    ((cursor detached-cursor))
  (error 'cluffer:cursor-detached))

(defmethod cluffer:detach-cursor
  ((cursor left-sticky-mixin))
  (setf (cursors (cluffer:line cursor))
	(remove cursor (cursors (cluffer:line cursor))))
  (change-class cursor 'detached-left-sticky-cursor)
  nil)

(defmethod cluffer:detach-cursor
  ((cursor right-sticky-mixin))
  (setf (cursors (cluffer:line cursor))
	(remove cursor (cursors (cluffer:line cursor))))
  (change-class cursor 'detached-right-sticky-cursor)
  nil)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Operations on cursors.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods on BEGINNING-OF-LINE-P.
;;;
;;; Given a cursor, return true if and only if it is at the beginning
;;; of the line.

;;; The default method just calls CURSOR-POSITION and returns true if
;;; and only if that position is 0.
(defmethod cluffer:beginning-of-line-p
    ((cursor attached-cursor))
  (zerop (cluffer:cursor-position cursor)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods on END-OF-LINE-P.

;;; The default method just calls CURSOR-POSITION and returns true if
;;; and only if that position is the same as the number of items in
;;; the line.
(defmethod cluffer:end-of-line-p
    ((cursor attached-cursor))
  (= (cluffer:cursor-position cursor)
     (cluffer:item-count (cluffer:line cursor))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods on INSERT-ITEM.

(defmethod cluffer:insert-item ((cursor attached-cursor) item)
  nil)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods on DELETE-ITEM.

(defmethod cluffer:delete-item ((cursor attached-cursor))
  nil)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods on ERASE-ITEM.

(defmethod cluffer:erase-item ((cursor attached-cursor))
  nil)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods on FORWARD-ITEM

(defmethod cluffer:forward-item ((cursor attached-cursor))
  (when (cluffer:end-of-line-p cursor)
    (error 'cluffer:end-of-line))
  (incf (cluffer:cursor-position cursor))
  nil)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods on BACKWARD-ITEM

(defmethod cluffer:backward-item ((cursor attached-cursor))
  (when (cluffer:beginning-of-line-p cursor)
    (error 'cluffer:beginning-of-line))
  (decf (cluffer:cursor-position cursor))
  nil)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods on BEGINNING-OF-LINE.
;;;
;;; Position the cursor at the beginning of the line.

(defmethod cluffer:beginning-of-line
    ((cursor attached-cursor))
  (setf (cluffer:cursor-position cursor) 0))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods on END-OF-LINE.
;;;
;;; Position the cursor at the end of the line.

(defmethod cluffer:end-of-line
    ((cursor attached-cursor))
  (setf (cluffer:cursor-position cursor)
	(cluffer:item-count (cluffer:line cursor))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods on ITEM-BEFORE-CURSOR.

(defmethod cluffer:item-before-cursor
    ((cursor attached-cursor))
  (when (cluffer:beginning-of-line-p cursor)
    (error 'cluffer:beginning-of-line))
  (aref (contents (cluffer:line cursor))
	(1- (cluffer:cursor-position cursor))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods on ITEM-AFTER-CURSOR.

(defmethod cluffer:item-after-cursor
    ((cursor attached-cursor))
  (when (cluffer:beginning-of-line-p cursor)
    (error 'cluffer:beginning-of-line))
  (aref (contents (cluffer:line cursor))
	(cluffer:cursor-position cursor)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods on CLUFFER-INTERNAL:SPLIT-LINE.

(defmethod cluffer-internal:split-line ((cursor attached-cursor))
  (let* ((pos (cluffer:cursor-position cursor))
	 (line (cluffer:line cursor))
	 (contents (contents line))
	 (new-contents (subseq contents pos))
	 (new-line (make-instance 'line
		     :cursors '()
		     :contents new-contents)))
    (setf (contents line)
	  (subseq (contents line) 0 pos))
    (setf (cursors new-line)
	  (loop for cursor in (cursors line)
		when (or (and (typep cursor 'right-sticky-mixin)
			      (>= (cluffer:cursor-position cursor) pos))
			 (and (typep cursor 'left-sticky-mixin)
			      (> (cluffer:cursor-position cursor) pos)))
		  collect cursor))
    (loop for cursor in (cursors new-line)
	  do (setf (cluffer:line cursor) new-line)
	     (decf (cluffer:cursor-position cursor) pos))
    (setf (cursors line)
	  (set-difference (cursors line) (cursors new-line)))
    new-line))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Methods on CLUFFER-INTERNAL:JOIN-LINE.

(defmethod cluffer-internal:join-line ((line1 line) (line2 line))
  (loop with length = (length (contents line1))
	for cursor in (cursors line2)
	do (setf (cluffer:line cursor) line1)
	   (incf (cluffer:cursor-position cursor) length))
  (setf (contents line1)
	(concatenate 'vector (contents line1) (contents line2)))
  nil)
