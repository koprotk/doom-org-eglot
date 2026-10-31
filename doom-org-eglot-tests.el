;;; doom-org-eglot-tests.el --- Tests for doom-org-eglot -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Daniel Muñoz

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Run with:
;;
;;   emacs -Q --batch -L . -l doom-org-eglot-tests.el \
;;         -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'doom-org-eglot)

(ert-deftest doom-org-eglot-test-server-program-understands-list-keys ()
  "A list of modes is a valid `eglot-server-programs' key."
  (let ((eglot-server-programs
         '(((python-mode python-ts-mode) "ty" "server")
           ((js-mode :language-id "javascript")
            "typescript-language-server" "--stdio"))))
    (should (equal (doom-org-eglot--server-program 'python-mode)
                   '("ty" "server")))
    (should (equal (doom-org-eglot--server-program 'python-ts-mode)
                   '("ty" "server")))
    (should (equal (doom-org-eglot--server-program 'js-mode)
                   '("typescript-language-server" "--stdio")))
    (should-not (doom-org-eglot--server-program 'emacs-lisp-mode))))

(ert-deftest doom-org-eglot-test-server-program-plain-and-derived-keys ()
  "Plain mode keys and derived modes both match."
  (let ((eglot-server-programs
         '((prog-mode . ("prog-server")))))
    (should (equal (doom-org-eglot--server-program 'prog-mode)
                   '("prog-server")))
    (should (equal (doom-org-eglot--server-program 'emacs-lisp-mode)
                   '("prog-server")))))

(ert-deftest doom-org-eglot-test-tangle-file ()
  "Relative `:tangle' paths expand against the Org buffer's directory."
  (let ((default-directory "/tmp/"))
    (should (equal (doom-org-eglot--tangle-file
                    '(python "print(1)" ((:tangle . "foo.py")))
                    nil)
                   "/tmp/foo.py"))
    (should-not (doom-org-eglot--tangle-file
                 '(python "print(1)" ((:tangle . "no")))
                 nil))
    (should-not (doom-org-eglot--tangle-file
                 '(python "print(1)" nil)
                 nil))))

(ert-deftest doom-org-eglot-test-temp-file-extension ()
  "Temporary files use the language's tangle extension."
  (let ((file (doom-org-eglot--temp-file "python" nil)))
    (unwind-protect
        (progn
          (should (file-exists-p file))
          (should (string-suffix-p ".py" file)))
      (delete-file file))))

(ert-deftest doom-org-eglot-test-advice-starts-eglot ()
  "The advice sets a file name and calls the local starter."
  (let ((eglot-server-programs '((python-mode . ("true"))))
        (started nil)
        (seen-file nil))
    (with-temp-buffer
      (org-mode)
      (insert "#+begin_src python :tangle foo.py\nprint(1)\n#+end_src\n")
      (goto-char (point-min))
      (search-forward "print")
      (cl-letf (((symbol-function 'org-babel-tangle)
                 (lambda (&rest _) 'tangled)))
        (let ((doom-org-eglot-starter-local
               (lambda ()
                 (setq started t
                       seen-file buffer-file-name))))
          (doom-org-eglot--edit-special (lambda (&rest _) 'edited))
          (should started)
          (should (string-suffix-p "/foo.py" seen-file)))))))

(ert-deftest doom-org-eglot-test-advice-skips-unknown-language ()
  "Blocks without an Eglot server are left to `org-edit-special'."
  (let ((eglot-server-programs nil)
        (started nil))
    (with-temp-buffer
      (org-mode)
      (insert "#+begin_src emacs-lisp\n(+ 1 1)\n#+end_src\n")
      (goto-char (point-min))
      (search-forward "+ 1")
      (let ((doom-org-eglot-starter-local (lambda () (setq started t))))
        (should (eq (doom-org-eglot--edit-special
                     (lambda (&rest _) 'edited))
                    'edited)))
      (should-not started))))

(ert-deftest doom-org-eglot-test-advice-skips-other-contexts ()
  "`C-c !' outside a source block keeps its normal behaviour."
  (let ((started nil))
    (with-temp-buffer
      (org-mode)
      (insert "* A heading\n")
      (goto-char (point-min))
      (let ((doom-org-eglot-starter-local (lambda () (setq started t))))
        (should (eq (doom-org-eglot--edit-special
                     (lambda (&rest _) 'edited))
                    'edited)))
      (should-not started))))

(provide 'doom-org-eglot-tests)
;;; doom-org-eglot-tests.el ends here
