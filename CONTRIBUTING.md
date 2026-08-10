# PayFlow Wallet — using this repo, credit, and upstream fixes

Most people using this project are **learners**, **portfolio builders**, or **buyers of a learning bundle**—not volunteer open-source maintainers. Your main thread is **`LEARNING-PATH.md`**. The sections below match that: first **how to reuse and describe the work**, then **how to contribute fixes upstream** if you choose to.

**Redistributing this repo (zip, course pack, fork):** Do **not** ship **`terraform.tfstate`**, **`.terraform/`**, real-filled **`terraform.tfvars`**, kubeconfigs, or `.env` files. Use the committed **placeholder** `terraform/aws/*/terraform.tfvars` patterns and let each learner fill their own secrets locally.

## If you use this repository (portfolio, course, fork, video)

When you reuse code, diagrams, or documentation in public (README, résumé, bootcamp syllabus, YouTube), **give credit** to the original project so others can find the source and so expectations stay clear about what you built versus what you started from:

- **Name:** PayFlow Wallet  
- **Source:** https://github.com/Ship-With-Zee/payflow-wallet  

A single line in your README or description is enough.

## If you contribute fixes upstream (GitHub)

Maintainers welcome **focused** bug reports and PRs that keep deploy docs and scripts accurate.

- **Issues** — What you ran, what you expected, logs or `./scripts/validate.sh` output when relevant.  
- **Pull requests** — One topic per PR; describe the problem and how your change fixes it.

### Before you open a PR

- Run **`./scripts/validate.sh`** (Docker Compose) when your change touches the app path or scripts.  
- If you change Node dependencies, run **`npm install`** in the affected service directory so `package-lock.json` stays consistent.  
- Match existing style in the files you touch; avoid unrelated refactors in the same PR.

### Questions

Use issues for questions that might help future readers (documentation gaps). For security-sensitive reports, use a private security advisory on GitHub if the repository has that enabled; otherwise follow any security contact published on the repo.

---

**Done here? → Return to [`LEARNING-PATH.md`](LEARNING-PATH.md)** — this file is not part of the weekly curriculum; open it when you need **credit language** or **upstream** contribution norms.
