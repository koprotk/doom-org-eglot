;;; doom-org-eglot.el --- Edit Org source blocks with Eglot -*- lexical-binding: t; -*-

;; Copyright (C) 2024 Anoncheg1
;; Copyright (C) 2026 Daniel Muñoz

;; Author: Daniel Muñoz <daniel.munoz.m@usach.cl>
;; Maintainer: Daniel Muñoz <daniel.munoz.m@usach.cl>
;; URL: https://github.com/koprotk/doom-org-eglot
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (org "9.6"))
;; Keywords: convenience, languages, tools
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this file.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; `doom-org-eglot' lets you edit Org source blocks with `C-c '' and
;; Eglot.
;;
;; Eglot needs a real file name to find the project and to tell the
;; language server which file it is editing, but `org-edit-special'
;; creates a buffer without one.  This package:
;;
;;   1. tangles the block to its `:tangle' file, or to a temporary file
;;      with the right extension when the block has no `:tangle',
;;   2. sets `buffer-file-name' and `default-directory' in the edit
;;      buffer, and
;;   3. starts Eglot, but only when a server is configured for the
;;      block's language.
;;
;; Blocks with a remote `:dir' (TRAMP) are tangled and edited on the
;; remote host, so Eglot starts the language server there too.
;;
;; Enable `doom-org-eglot-mode' and keep using `C-c '' as usual:
;;
;;   (require 'doom-org-eglot)
;;   (doom-org-eglot-mode 1)
;;
;; For Doom Emacs:
;;
;;   ;; packages.el
;;   (package! doom-org-eglot
;;     :recipe (:host github :repo "koprotk/doom-org-eglot"))
;;
;;   ;; config.el
;;   (use-package! doom-org-eglot
;;     :after org
;;     :config (doom-org-eglot-mode 1))
;;
;; This is a fork of Anoncheg1/org-eglot, which packaged the snippet
;; from https://github.com/joaotavora/eglot/issues/216#issuecomment-1052931508

;;; Code:

(require 'eglot)
(require 'ob-tangle)
(require 'org)
(require 'seq)

(defgroup doom-org-eglot nil
  "Edit Org source blocks with Eglot."
  :group 'org
  :prefix "doom-org-eglot-")

(defcustom doom-org-eglot-starter #'eglot-ensure
  "Function used to start Eglot in a remote source block.
The block's `:dir' is a remote TRAMP directory, so Eglot connects to
a language server running on that host.

Set this to a wrapper around `eglot-ensure' if you need to prepare
the connection first, for example:

  (setq doom-org-eglot-starter
        (lambda ()
          (eglot-shutdown-all)
          (eglot-ensure)))"
  :type 'function
  :group 'doom-org-eglot)

(defcustom doom-org-eglot-starter-local #'eglot-ensure
  "Function used to start Eglot in a local source block.
See `doom-org-eglot-starter' for the remote counterpart."
  :type 'function
  :group 'doom-org-eglot)

(defcustom doom-org-eglot-language-extensions
  '(("C" . "c") ("c" . "c") ("c++" . "cpp") ("cpp" . "cpp")
    ("clojure" . "clj") ("css" . "css") ("elixir" . "ex")
    ("emacs-lisp" . "el") ("elisp" . "el") ("go" . "go")
    ("haskell" . "hs") ("html" . "html") ("java" . "java")
    ("javascript" . "js") ("js" . "js") ("json" . "json")
    ("lisp" . "lisp") ("lua" . "lua") ("markdown" . "md")
    ("perl" . "pl") ("php" . "php") ("python" . "py")
    ("ruby" . "rb") ("rust" . "rs") ("scheme" . "scm")
    ("sh" . "sh") ("bash" . "sh") ("shell" . "sh")
    ("sql" . "sql") ("typescript" . "ts") ("ts" . "ts")
    ("yaml" . "yaml"))
  "File extensions used for temporary files, by Org language.
`org-babel-tangle-lang-exts' is consulted first; this alist is only a
fallback for languages whose Babel support has not been loaded yet."
  :type '(alist :key-type string :value-type string)
  :group 'doom-org-eglot)

(defun doom-org-eglot--server-program (mode)
  "Return the Eglot contact configured for MODE, or nil.
MODE is a major mode symbol.

Unlike a plain `assq' lookup, this understands all the key forms
allowed in `eglot-server-programs': a single mode, a list of modes,
or a mode followed by a property list (as in
`(js-mode :language-id \"javascript\")')."
  (catch 'doom-org-eglot--found
    (dolist (entry eglot-server-programs)
      (let ((modes (car entry)))
        (when (if (or (symbolp modes) (keywordp (cadr modes)))
                  (provided-mode-derived-p mode modes)
                (seq-some (lambda (m)
                            (provided-mode-derived-p
                             mode (if (consp m) (car m) m)))
                          modes))
          (throw 'doom-org-eglot--found (cdr entry)))))
    nil))

(defun doom-org-eglot--tangle-file (info dir)
  "Return the file the block described by INFO should be tangled to.
Return nil when the block has no usable `:tangle' value.  DIR is the
block's `:dir' value.

Relative `:tangle' paths in remote blocks are expanded against DIR;
local blocks keep Org's usual behaviour of resolving them against the
Org file's directory."
  (let ((tangle (assoc-default :tangle (nth 2 info))))
    (when (and (stringp tangle)
               (not (member tangle '("no" "yes"))))
      (expand-file-name
       tangle
       (if (and dir (file-remote-p dir))
           (file-name-as-directory dir)
         default-directory)))))

(defun doom-org-eglot--extension (lang)
  "Return the file extension, without the dot, for Org language LANG."
  (or (cdr (assoc lang org-babel-tangle-lang-exts))
      (cdr (assoc lang doom-org-eglot-language-extensions))
      "txt"))

(defun doom-org-eglot--temp-file (lang dir)
  "Create a temporary file for LANG and return its name.
When DIR is non-nil, create the file there; DIR may be a remote TRAMP
directory.  Otherwise use the system temporary directory, as given by
the variable `temporary-file-directory'."
  (let* ((ext (doom-org-eglot--extension lang))
         (temporary-file-directory
          (cond
           ((and dir (file-directory-p dir))
            (file-name-as-directory dir))
           ((and dir (file-remote-p dir))
            (concat (file-remote-p dir) "/tmp/"))
           (t temporary-file-directory))))
    (make-temp-file "doom-org-eglot-" nil (concat "." ext))))

(defun doom-org-eglot--edit-special (orig-fn &rest args)
  "Call ORIG-FN with ARGS, then start Eglot in the source edit buffer.
Eglot is only started when a server is configured for the block's
language.  The block is tangled to its `:tangle' file when it has one;
otherwise a temporary file is used so Eglot still has a real file name."
  (let* ((info (and (org-in-src-block-p)
                    (org-babel-get-src-block-info)))
         (lang (nth 0 info))
         (params (nth 2 info))
         (dir (cdr (assq :dir params)))
         (mode (and info (org-src-get-lang-mode lang)))
         (server (and mode (doom-org-eglot--server-program mode))))
    (if (not server)
        (apply orig-fn args)
      (let* ((tangle-file (doom-org-eglot--tangle-file info dir))
             (target (or tangle-file
                         (doom-org-eglot--temp-file lang dir))))
        (when tangle-file
          ;; Tangle while point is still in the Org buffer.  Bind
          ;; `default-directory' so relative paths in remote blocks are
          ;; resolved on the remote host.
          (let ((default-directory
                 (if (and dir (file-remote-p dir))
                     (file-name-as-directory dir)
                   default-directory)))
            (org-babel-tangle '(4))))
        (prog1 (apply orig-fn args)
          ;; We are now in the source edit buffer.
          (when dir
            (setq-local default-directory
                        (file-name-as-directory (expand-file-name dir))))
          (unless tangle-file
            ;; Some servers read the file from disk instead of trusting
            ;; the text sent in `textDocument/didOpen'.
            (let ((buffer-file-name nil))
              (write-region (point-min) (point-max) target nil 'silent)))
          (setq-local buffer-file-name target)
          (funcall (if (and dir (file-remote-p dir))
                       doom-org-eglot-starter
                     doom-org-eglot-starter-local)))))))

;;;###autoload
(define-minor-mode doom-org-eglot-mode
  "Edit Org source blocks with Eglot.
When enabled, `org-edit-special' tangles the block, gives the edit
buffer a real file name, and starts Eglot when the block's language
has a configured server."
  :global t
  :group 'doom-org-eglot
  (if doom-org-eglot-mode
      (advice-add 'org-edit-special :around #'doom-org-eglot--edit-special)
    (advice-remove 'org-edit-special #'doom-org-eglot--edit-special)))

(provide 'doom-org-eglot)
;;; doom-org-eglot.el ends here
