;;; named-pipe.el --- read from named pipes -*- lexical-binding: t -*-

;; Copyright Steven Allen <steven@stebalien.com>

;; Author: Steven Allen <steven@stebalien.com>
;; URL: https://github.com/Stebalien/named-pipe.el
;; Version: 0.0.1
;; Package-Requires: ((emacs "27.0"))
;; Keywords: pipe, pager

;; This file is not part of GNU Emacs.

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:

;; An emacs package for reading from named-pipes into pager buffers.
;;
;; This package is primarily useful to pipe data from a shell into
;; emacs using the attached script.

;;; Code:
(eval-when-compile (require 'cl-lib))
(require 'ansi-color)

(defgroup named-pipe-pager nil
  "Pager for reading from named pipes."
  :group 'tools)

(defcustom named-pipe-pager-buffer-name "*pager*"
  "The default name for pager buffers."
  :type 'string
  :group 'named-pipe-pager)

(defcustom named-pipe-pager-colorize t
  "Process ANSI escape sequences to colorize the pager's text."
  :type '(choice (const :tag "Colorize" t)
		 (const :tag "Disabled" nil)
		 (const :tag "Strip" strip))
  :group 'named-pipe-pager)

(defcustom named-pipe-pager-mode-hook nil
  "Hook run in new pager buffers."
  :type 'hook
  :group 'named-pipe-pager)

(defcustom named-pipe-pager-auto-mode t
  "Attempt to automatically set the pager buffer's mode based on thetext."
  :type '(choice (const :tag "On" t)
		 (const :tag "Off" nil)
		 (function :tag "Custom"))
  :group 'named-pipe-pager)

(defvar named-pipe-pager-mode-map (make-sparse-keymap))

(define-minor-mode named-pipe-pager-mode
  "Minor mode applied to all named-pipe pagers.
By default, this mode does nothing except the buffer to be
read-only. However, it provides a convenient place to attach
keybindings and hooks that should apply to all pagers.

This mode should not be manually enabled."
  :group 'named-pipe-pager
  :keymap 'named-pipe-pager-mode-map
  :after-hook 'named-pipe-pager-mode-hook
  (read-only-mode))

(defun named-pipe--pager-filter (proc string)
  (when (buffer-live-p (process-buffer proc))
    (with-current-buffer (process-buffer proc)
      (save-excursion
        ;; Insert the text, advancing the process marker.
	(let* ((no-mode (eq major-mode 'fundamental-mode))
	       (inhibit-read-only t)
	       (filter (cond
			((and no-mode (eq named-pipe-pager-colorize t))
			 (if (fboundp 'xterm-color-filter)
			     'xterm-color-filter
			   'ansi-color-apply))
			((eq named-pipe-pager-colorize 'strip)
			 'ansi-color-filter-apply)
			(t 'identity))))
	  (goto-char (process-mark proc))
	  (insert (funcall filter string))
	  (when (and named-pipe-pager-auto-mode no-mode)
	    (set-auto-mode t))
	  (set-marker (process-mark proc) (point)))))))

;;;###autoload
(cl-defun named-pipe-read (pipe-name &key (buffer (current-buffer)) (sentinel #'ignore) filter)
  (make-process
   :name (concat "|" pipe-name)
   :connection-type 'pipe
   :buffer buffer
   :command `("cat" ,pipe-name)
   :sentinel sentinel
   :filter filter))

;;;###autoload
(cl-defun named-pipe-read-lines (pipe-name fn &key done)
  (named-pipe-read pipe-name
   :buffer nil
   :filter (lambda (proc string)
             (let ((lines (split-string string "\n" nil nil))
                   (carry (or (process-get proc 'named-pipe--line-carry) "")))
               (unless (string-empty-p carry)
                 (setq lines (cons (concat carry (car lines)) (cdr lines))))
               (while (cdr lines)
                 (funcall fn (car lines))
                 (setq lines (cdr lines)))
               (process-put proc 'named-pipe--line-carry (car lines))))
   :sentinel (if done
                 (lambda (proc _status)
                   (unless (process-live-p proc)
                     (funcall done (or (process-get proc 'named-pipe--line-carry) ""))))
               #'ignore)))

;;;###autoload
(cl-defun named-pipe-pager (pipe-name &optional (buffer (generate-new-buffer named-pipe-pager-buffer-name)))
  "Read the named pipe into a read-only 'pager' buffer."
  (with-current-buffer buffer
    (named-pipe-read pipe-name :filter #'named-pipe--pager-filter)
    (named-pipe-pager-mode)
    (pop-to-buffer buffer)))

(provide 'named-pipe)
