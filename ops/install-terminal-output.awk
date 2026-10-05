# This is the only bridge from the Go installer's mixed diagnostic stream to
# the operator's terminal. Keep Docker, SQL, systemd and invariant output in
# install-last-run-output.txt, not here. fflush makes each step visible live.
/^\[[0-9]+\/[0-9]+\] [A-Za-z][A-Za-z +()-]* +(OK|RUNNING|DONE|FAILED: This part of installation could not finish\.|FAILED — falling back to full migrations|no seed image — full migrations will run)$/ {
    print
    fflush()
    next
}
/^  (Starting every service:|All services are running\.|Fetching seed |No seed image available|Restoring seed|Pausing application traffic|Application traffic |The database held older passwords|the web server \(proxy\) has missing published ports|the database \(db\) has missing published ports|the API service \(rest\) has missing published ports|the web app \(app\) has missing published ports|the background worker \(worker\) has missing published ports|Database updates will be applied\.|The database is up to date\.|Creating |Configuring |Applying |Downloading |Installing |Checking |Waiting |Running |Copying |Enabling |Recorded installed version )/ {
    print
    fflush()
    next
}
/^INSTALL_SERVICE: (the API service \(rest\)|the web app \(app\)|the background worker \(worker\)|the web server \(proxy\)) keeps restarting; its recent logs are in the install log\.$/ {
    sub(/^INSTALL_SERVICE: /, "")
    print
    fflush()
    next
}
/^  (the database \(db\)|the web server \(proxy\)|the API service \(rest\)|the web app \(app\)|the background worker \(worker\)|the automatic update service \(upgrade\)): (running|restarting|exited|stopped|created|dead|paused|removing|absent|active|inactive|failed|activating|deactivating|unknown)( \((healthy|unhealthy|starting)\))?$/ {
    print
    fflush()
    next
}
/^INSTALL_SERVICE: (the database \(db\)|the web server \(proxy\)|the API service \(rest\)|the web app \(app\)|the background worker \(worker\)) (was never started|keeps restarting|is still starting|is running but reports unhealthy|has stopped|was created but could not start|is (running|restarting|exited|stopped|dead|not ready|missing published ports)); its recent logs are in the install log\.$/ {
    sub(/^INSTALL_SERVICE: /, "")
    print
    fflush()
    next
}
/^(Installation complete!|All steps complete\.|The previous restart finished\. Continuing installation\.)/ {
    print
    fflush()
}
# The install-state announcement (cli/cmd/install.go logInstallState) and the
# two fixed transitions around it. The operator must see which situation the
# installer detected before any step line: an interrupted first install says it
# is continuing, not starting over (5-install-interrupted-first-run asserts
# this line; it was filtered out). Whole-line fixed literals only.
# TestInstallTerminalWriterShowsEveryInstallState runs logInstallState for
# every state and checks each line reaches the terminal exactly once.
/^(Preparing a new StatBus installation\.|An upgrade is already running\. Wait for it to finish, then retry if needed\.|The previous upgrade stopped unexpectedly\. Recovery will run now\.|Continuing the upgrade on the new binary after the planned handoff\.|Installation settings are incomplete\. Repair will run now\.|The database is not available\. Repair will run now\.|The database exists but setup stopped before it was finished\. Continuing where it stopped\.|This installation is too old for automatic repair\. Follow the documented manual upgrade path\.|A scheduled upgrade is ready and will run now\.|A previous database restore did not finish\. It will be retried now\.|Checking the existing installation\.|  The database and installed program differ\. Repair will reconcile them\.)$/ {
    print
    fflush()
    next
}
/^(Recovery finished\. Checking the installation again\.|The database could not be checked\. Continuing with installation repair\.|Restoring generated settings before checking the installation\.)$/ {
    print
    fflush()
    next
}
# Fixed consequential notices outside logInstallState (review2 findings 2, 3).
# The configuration-refusal banner's heading and closing sentence pass, but
# never the stored refusal message or its timestamp: those stay in the
# installation diagnostics file the operator is pointed to. The restore
# re-attempt legend, its success forecast and the degraded-outcome advice are
# fixed text and pass verbatim.
/^(⚠ The last start of the upgrade service refused its configuration:|If this run below fixes the config, the marker clears automatically\.|Re-attempting the restore from the retained snapshot \(this is what `\.\/sb install` does here\)\.\.\.|Restore complete — the system is running normally on the previous version\.|  The upgrade that failed has been rolled back\. To move forward:|    • Find a newer release:  \.\/sb upgrade check|    • The version that failed will fail the same way — try a LATER release when one is available\.|  The database restore could not be completed; the system is still degraded\.|  Next: contact SSB support and involve your IT staff\. Keep this box as-is for diagnosis;)$/ {
    print
    fflush()
    next
}
# The degraded-restore closing line names the box's own checkout by absolute
# path (upgrade.InstallCommand: `cd <checkout> && ./sb install`). Only that
# grammar passes: a plain path, then the fixed sentence, nothing appended.
# TestInstallTerminalWriterShowsEveryInstallState feeds the real
# restoreReattemptFailure text through this filter.
/^  re-running `cd (~|\/)[A-Za-z0-9_.\/~+-]* && \.\/sb install` will re-attempt the same restore$/ {
    print
    fflush()
    next
}
/^A previous upgrade's rollback did not finish restoring the database \(row id=[0-9]+\)\.$/ {
    print
    fflush()
    next
}
# upgrade.LiveInstallHolderRefusal: the one dynamic state line. Only its exact
# grammar passes (RFC3339 time, optional numeric PID, fixed remedy), so no
# other text can ride along to the operator's terminal.
/^an installation (started at 2[0-9]{3}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](Z|[+-]([01][0-9]|2[0-3]):[0-5][0-9])( \(process [1-9][0-9]*\))? )?is still running\. Wait for it to finish, then run the same install command again$/ {
    print
    fflush()
    next
}
