# Contributing to Armbian Config

We would love to have you join the Armbian developers community! Below summarizes the processes that we follow.

## Reporting issues

Before [reporting an issue](https://github.com/armbian/configng/issues/new/choose), check our [backlog of open issues](https://github.com/armbian/configng/issues) and [pull requests](https://github.com/armbian/configng/pulls) to see if someone else has already reported or working on it. If an issues is already open, feel free to add your scenario, or additional information, to the discussion. Or simply "subscribe" to it to be notified when it is updated.

If you find a new issue with the project please let us hear about it! The most important aspect of a bug report is that it includes enough information for us to reproduce it. So, please include as much detail as possible and try to remove the extra stuff that does not really relate to the issue itself. The easier it is for us to reproduce it, the faster it will be fixed!

Please do not include any private/sensitive information in your issue! We are not responsible for your privacy, this is open source software.

## Working on issues

Once you have decided to contribute to Armbian by working on an issue, check our backlog of open (or [JIRA](https://armbian.atlassian.net/jira/dashboards/10000) issues open by the team) looking for any that do not have an "In Progress" label attached to it. Often issues will be assigned to someone, to be worked on at a later time. If you have the time to work on the issue now add yourself as an assignee, and set the "In Progress" label if you are a member of the “Containers” GitHub organization. If you can not set the label, just add a quick comment in the issue asking that the “In Progress” label be set and a member will do so for you.

Please be sure to review the [Development Code Review Procedures and Guidelines](https://docs.armbian.com/Development-Code_Review_Procedures_and_Guidelines/) as well before you begin.

## PR and issues labeling

Labels are defined in [.github/labels.yml](.github/labels.yml) YAML file. They are automatically recreated upon change. Require at least `Triage` users permission on repository. [Request access](https://github.com/armbian/configng#contact) if you cannot change labels!

Most of labels are self explanoritary but here are short instructions on how to use them:

Automated on PR:
- `size/small`, `size/medium`, `size/large` is determined automatically from the size of the PR
- `desktop`, `hardware` and `software` is determined automatically depending on location of the changes
- `needs review` - is added by default
- `ready to merge` - when you get approval

Manual on PR:
- `02` `05` `08` `11` milestone - determine into which release the PR should go
- `work in progress` - when you are still working on
- `help needed` - when you are desperate and cannot move on

Labeling Issues:
- `bug` when it is clear that it is our bug, `not our bug` if its clearly not ours, `duplicate` if issue already exists
- `discussion`, when needed, `user error` when we know it is a problem on the other side
- `can be closed` for stalled issues

## Contributing

This section describes how to start contributing to Armbian.

### Prepare your environment

* Create an Ubuntu 22.04 VM with VirtualBox or any other suitable hypervisor. 
* Install [Github CLI tool](https://github.com/cli/cli/blob/trunk/docs/install_linux.md)
* Configure git:

```bash
    git config --global user.email "your@email.com"
    git config --global user.name "Your Name"
```

* Generate GPG key

```bash
    gpg --generate-key
```

* Generate Github login [token](https://docs.github.com/en/free-pro-team@latest/github/authenticating-to-github/creating-a-personal-access-token)
* Login to Github (you only have to do the steps above once)

```bash
    gh auth login --with-token <<< 'your_token'
```

### Fork and clone Armbian Config

* Fork armbian/configng, clone and add remote

```bash
    gh repo fork armbian/configng --clone=true --remote=true
```

* Create branch

```bash
    cd configng
    git checkout -b your_branch_name # change branch name for your patch
```

### Testing features

```bash
tools/config-assemble.sh -p # Use -t for testing
bin/armbian-config
```

## Submitting pull requests

No Pull Request (PR) is too small! Typos, additional comments in the code, new test cases, bug fixes, new features, more documentation, ... everything is welcome!

While bug fixes can first be identified via an "issue", that is not required for things mentioned above. It is fine to just open up a PR with the fix, but make sure you include the same information you would have included in an actual issue - like how to reproduce it.

PRs for new features should include some background on what use cases the new code is trying to address. When possible and when it makes sense, try to break-up larger PRs into smaller parts - it is easier to [review](https://github.com/armbian/configng/pulls?q=is%3Apr+is%3Aopen+review%3Arequired+label%3A%22Ready+%3Aarrow_right%3A%22) smaller code changes. But only if those smaller ones make sense as stand-alone PRs.

You should squash your commits into logical pieces of work that can be reviewed separate from the rest of the PRs. Squashing down to just one commit is ok as well, since in the end the entire PR will be reviewed anyway. If in doubt, squash.

### Describe your changes in commit messages

Describe your problem(s). Whether your patch is a one-line bug fix or 5000 lines including a new feature, there must be an underlying problem that motivated you to do this work. Your description should work to convince the reviewer that there is a problem worth fixing and that it makes sense for them to read past the first paragraph. This means providing comprehensive details about the issue, including, but not limited to: 

* How the problem presented itself
* How to replicate the problem
* Why you feel it is important for this issue to be resolved

## Communications

For general questions and discussion, please use the IRC `#armbian`, `#armbian-devel` or `#armbian-desktop` on Libera.Chat or [Discord server](http://discord.armbian.com). Most IRC and Discord channels are bridged and recorded.

For discussions around issues/bugs and features, you can use the [GitHub issues](https://github.com/armbian/configng/issues), the [PR tracking system](https://github.com/armbian/configng/pulls) or our [Jira ticketing system](https://armbian.atlassian.net/jira/software/c/projects/AR/issues/?filter=allissues).

## Other ways to contribute

* [Become a new board maintainer](https://docs.armbian.com/Board_Maintainers_Procedures_and_Guidelines/)
* [Apply for one of the position](https://forum.armbian.com/staffapplications/)
* [Help us covering costs](https://forum.armbian.com/subscriptions/)
* [Help community members in the Forum](https://forum.armbian.com/)
* [Check forum announcements section for any requests for help from the community](https://forum.armbian.com/forum/37-announcements/)
