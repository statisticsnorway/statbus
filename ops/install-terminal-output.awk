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
/^(Installation complete!|All steps complete\.|The previous restart finished\. Continuing installation\.)/ {
    print
    fflush()
}
