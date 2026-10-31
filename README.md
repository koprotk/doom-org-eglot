# doom-org-eglot

Edit Org source blocks with [Eglot](https://github.com/joaotavora/eglot) —
completion, diagnostics, and refactoring for code embedded in `.org` files.

Eglot needs a real file name to find the project and to tell the language
server which file it is editing, but `org-edit-special` (`C-c '`) creates a
buffer without one. This package bridges that gap:

1. tangles the block to its `:tangle` file, or to a temporary file with the
   right extension when the block has no `:tangle`;
2. sets `buffer-file-name` and `default-directory` in the edit buffer;
3. starts Eglot — but only when a server is configured for the block's
   language, so `C-c '` never prompts you to pick a server.

Blocks with a remote `:dir` (TRAMP) are tangled and edited on the remote host,
so the language server runs there too.

> **Note:** this is a fork of
> [Anoncheg1/org-eglot](https://github.com/Anoncheg1/org-eglot), renamed and
> maintained by [@koprotk](https://github.com/koprotk). It fixes the
> `eglot-server-programs` handling (list keys such as
> `((python-mode python-ts-mode) ...)`), loads Eglot before reading its
> variables, and leaves unsupported languages alone. The original idea comes
> from [joaotavora/eglot#216](https://github.com/joaotavora/eglot/issues/216#issuecomment-1052931508).

## Requirements

- Emacs 29.1 or newer (Eglot and TRAMP are built in)
- Org 9.6 or newer
- The language server for whichever language you edit

## Installation

### Doom Emacs

`packages.el`:

```elisp
(package! doom-org-eglot
  :recipe (:host github :repo "koprotk/doom-org-eglot"))
```

`config.el`:

```elisp
(use-package! doom-org-eglot
  :after org
  :config (doom-org-eglot-mode 1))
```

Then run `doom sync` and restart Emacs.

### `package-vc` (Emacs 29+)

```elisp
(package-vc-install
 '(doom-org-eglot :url "https://github.com/koprotk/doom-org-eglot"))
```

### Manual

```elisp
(add-to-list 'load-path "/path/to/doom-org-eglot")
(require 'doom-org-eglot)
(doom-org-eglot-mode 1)
```

## Usage

Enable `doom-org-eglot-mode`, put point inside a source block, and press
`C-c '` as usual. For best results give the block a `:tangle` file inside your
project:

```org
#+begin_src python :tangle src/module.py
def greet(name: str) -> str:
    return f"Hello, {name}!"
#+end_src
```

The block is tangled before the edit buffer opens, and the server sees
`src/module.py` as the file being edited. Save (`C-c '`) and the edit buffer is
written back to the `.org` file as usual.

Without `:tangle`, the block is written to a temporary file with the language's
usual extension. That works, but the server may treat the temporary directory
as the project root, so imports and dependencies can be less accurate. Prefer
`:tangle` when you can.

### Remote hosts (TRAMP)

Use a remote `:dir` and the block is tangled and edited on that host:

```org
#+begin_src python :dir /ssh:server:/home/user/project :tangle main.py
print("runs on server")
#+end_src
```

Eglot connects to a language server on `server`, with the buffer's
`default-directory` and `buffer-file-name` pointing at the remote paths.

## Customization

| Variable | Default | Meaning |
|---|---|---|
| `doom-org-eglot-starter` | `eglot-ensure` | Starts Eglot for remote blocks |
| `doom-org-eglot-starter-local` | `eglot-ensure` | Starts Eglot for local blocks |

For example, to drop stale connections before reconnecting:

```elisp
(setq doom-org-eglot-starter
      (lambda ()
        (eglot-shutdown-all)
        (eglot-ensure)))
```

Server configuration itself is plain Eglot, e.g. for Doom users:

```elisp
(with-eval-after-load 'python
  (set-eglot-client! '(python-mode python-ts-mode) '("ty" "server")))
```

## Tests

```sh
emacs -Q --batch -L . -l doom-org-eglot-tests.el \
      -f ert-run-tests-batch-and-exit
```

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
