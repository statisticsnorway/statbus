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
# The install-state announcement (cli/cmd/install.go logInstallState). The
# operator must see which situation the installer detected before any step
# line: an interrupted first install says it is continuing, not starting over
# (5-install-interrupted-first-run asserts this line; it was filtered out).
# TestInstallTerminalWriterShowsEveryInstallState keeps this list in sync.
/^(Preparing a new StatBus installation\.|An upgrade is already running\. Wait for it to finish, then retry if needed\.|The previous upgrade stopped unexpectedly\. Recovery will run now\.|Installation settings are incomplete\. Repair will run now\.|The database is not available\. Repair will run now\.|The database exists but setup stopped before it was finished\. Continuing where it stopped\.|This installation is too old for automatic repair\. Follow the documented manual upgrade path\.|A scheduled upgrade is ready and will run now\.|A previous database restore did not finish\. It will be retried now\.|Checking the existing installation\.|  The database and installed program differ\. Repair will reconcile them\.)$/ {
    print
    fflush()
}
