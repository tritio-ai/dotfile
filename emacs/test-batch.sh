#!/usr/bin/env sh
set -eu

script_dir=$(cd "$(dirname "$0")" && pwd -P)
repo_dir=$(cd "$script_dir/.." && pwd -P)
. "$repo_dir/lib/packages.sh"
packages_repo=$(dotfile_packages_root "$repo_dir")
test_home=$(mktemp -d "${TMPDIR:-/tmp}/dotfile-emacs-batch.XXXXXX")

cleanup() {
  rm -rf "$test_home"
}
trap cleanup EXIT HUP INT TERM

HOME="$test_home" \
DOTFILE_EMACS_STATE_DIR="$test_home/.emacs.d/dotfile-emacs" \
DOTFILE_EMACS_PACKAGE_CACHE="$packages_repo/emacs/packages" \
"${EMACS:-emacs}" -Q --batch -l "$script_dir/early-init.el" -l "$script_dir/init.el" \
  --eval "(dolist (feature '(bind-key use-package compat vertico marginalia orderless consult corfu cape popon corfu-terminal which-key avy eat yaml-mode dockerfile-mode markdown-mode diff-hl multiple-cursors rainbow-delimiters embark embark-consult tempel dotfile-emacs-prompt)) (unless (require feature nil t) (error \"Cannot require %s\" feature)))" \
  --eval '(unless (and (equal (face-background (quote default) nil t) "#1e1e2e") (equal (face-foreground (quote default) nil t) "#cdd6f4") (eq (face-attribute (quote default) :weight nil (quote default)) (quote bold))) (error "Catppuccin Mocha default face not applied"))' \
  --eval '(dolist (package (quote (use-package which-key))) (unless (cl-some (lambda (desc) (file-in-directory-p (file-truename (package-desc-dir desc)) (file-truename package-user-dir))) (cdr (assq package package-alist))) (error "%s was not installed into package-user-dir" package)))' \
  --eval '(unless (bound-and-true-p which-key-mode) (error "which-key-mode not enabled"))' \
  --eval '(unless (eq (key-binding (kbd "C-z ;")) (quote dotfile-emacs-prompt-copy)) (error "Missing prompt shortcut"))' \
  --eval '(dolist (spec (quote (("C-x SPC" set-mark-command) ("C-x >" end-of-buffer) ("C-x <" beginning-of-buffer) ("C-c c" replace-string) ("C-c q" read-only-mode) ("M-F" subword-right) ("M-B" subword-left) ("C-c Q" dotfile-emacs-sudo-edit-current-buffer)))) (unless (eq (key-binding (kbd (car spec))) (cadr spec)) (error "Missing shortcut %s" (car spec))))' \
  --eval '(unless (eq (key-binding (kbd "C--")) (quote dotfile-emacs-text-scale-decrease)) (error "Missing font decrease shortcut"))' \
  --eval '(unless (eq (key-binding (kbd "C-=")) (quote dotfile-emacs-text-scale-increase)) (error "Missing font increase shortcut"))' \
  --eval '(unless (eq (key-binding (kbd "C-+")) (quote dotfile-emacs-text-scale-increase)) (error "Missing literal font increase shortcut"))' \
  --eval '(unless (eq (key-binding (kbd "C-x B")) (quote dotfile-emacs-switch-to-scratch)) (error "Missing scratch shortcut"))' \
  --eval '(unless (keymapp (lookup-key global-map (kbd "C-c p"))) (error "Project prefix is not active"))' \
  --eval '(dolist (spec (quote (("M-n" forward-paragraph) ("M-p" backward-paragraph) ("C-x p" nil) ("C-c k" delete-frame) ("C-c y" duplicate-line) ("C-0" (dotfile-emacs-legacy-text-scale-reset dotfile-emacs-text-scale-reset)) ("C-_" undo)))) (let ((binding (key-binding (kbd (car spec)))) (expected (cadr spec))) (when (and expected (not (if (listp expected) (memq binding expected) (eq binding expected)))) (error "Missing legacy shortcut %s" (car spec)))))' \
  --eval '(dolist (var (quote (bookmark-save-flag recentf-max-saved-items history-length kill-ring-max scroll-margin))) (unless (boundp var) (error "Missing legacy setting %s" var)))' \
  --eval '(unless (eq (lookup-key eat-mode-map (kbd "C-x B")) (quote dotfile-emacs-switch-to-scratch)) (error "Missing Eat scratch shortcut in eat-mode-map"))' \
  --eval '(dolist (spec (quote ((eat-mode-map "C-c C-e" eat-emacs-mode) (eat-mode-map "C-c C-s" eat-semi-char-mode) (eat-mode-map "C-c C-d" eat-char-mode) (eat-semi-char-mode-map "C-c C-e" eat-emacs-mode) (eat-semi-char-mode-map "C-c C-s" eat-semi-char-mode) (eat-semi-char-mode-map "C-c C-d" eat-char-mode) (eat-line-mode-map "C-c C-e" eat-emacs-mode) (eat-line-mode-map "C-c C-s" eat-semi-char-mode) (eat-line-mode-map "C-c C-d" eat-char-mode) (eat-eshell-emacs-mode-map "C-c C-e" eat-eshell-emacs-mode) (eat-eshell-emacs-mode-map "C-c C-s" eat-eshell-semi-char-mode) (eat-eshell-emacs-mode-map "C-c C-d" eat-eshell-char-mode) (eat-eshell-semi-char-mode-map "C-c C-e" eat-eshell-emacs-mode) (eat-eshell-semi-char-mode-map "C-c C-s" eat-eshell-semi-char-mode) (eat-eshell-semi-char-mode-map "C-c C-d" eat-eshell-char-mode)))) (let ((map (symbol-value (nth 0 spec))) (key (nth 1 spec)) (command (nth 2 spec))) (unless (eq (lookup-key map (kbd key)) command) (error "Missing Eat mode switch %s in %s" key (nth 0 spec)))))' \
  --eval '(dolist (map-symbol (quote (eat-char-mode-map eat-eshell-char-mode-map))) (let ((prefix (lookup-key (symbol-value map-symbol) (kbd "C-x")))) (unless (keymapp prefix) (error "Eat char C-x is not a prefix in %s" map-symbol)) (unless (eq (lookup-key (symbol-value map-symbol) (kbd "C-x B")) (quote dotfile-emacs-switch-to-scratch)) (error "Missing Eat char scratch shortcut in %s" map-symbol)) (unless (eq (lookup-key prefix [t]) (quote dotfile-emacs-eat-self-input-key-sequence)) (error "Eat char C-x relay missing in %s" map-symbol))))' \
  --eval '(dolist (map-symbol (quote (eat-char-mode-map eat-eshell-char-mode-map))) (unless (eq (lookup-key (symbol-value map-symbol) (kbd "C-c")) (quote eat-self-input)) (error "Eat char C-c should remain terminal input in %s" map-symbol)))' \
  --eval '(unless (eq (key-binding (kbd "C-c j")) (quote avy-goto-char-timer)) (error "Missing avy shortcut"))' \
  --eval '(let ((template (dotfile-emacs-prompt--template-by-key "codex-implement"))) (unless (string-match-p "{{task}}" (plist-get template :body)) (error "Prompt template parser failed")))' \
  --eval '(require (quote org))' \
  --eval '(unless (and org-src-fontify-natively org-startup-with-inline-images (equal org-edit-src-content-indentation 0) (not org-src-preserve-indentation)) (error "Org defaults not applied"))' \
  --eval '(with-temp-buffer (org-mode) (unless (eq (local-key-binding (kbd "C-c i")) (quote dotfile-emacs-org-insert)) (error "Missing Org insert binding")) (unless (eq (local-key-binding (kbd "C-c w")) (quote dotfile-emacs-org-copy-block-content)) (error "Missing Org copy binding")))' \
  --eval '(message "dotfile Emacs batch test loaded")'
