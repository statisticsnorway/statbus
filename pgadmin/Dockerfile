# Custom pgAdmin 4 image with SSLSNI patch
# Based on https://github.com/pgadmin-org/pgadmin4/pull/9537
# This patch fixes SSL direct mode connection failure with sslsni parameter
# Required until pgAdmin releases a version including this fix (merged to master Jan 2026)

FROM dpage/pgadmin4:latest

USER root

# Apply the SSLSNI boolean-to-integer conversion patch
# The patch converts boolean values (true/false) to integers (1/0) for
# sslcompression and sslsni parameters, which libpq requires
COPY apply-sslsni-patch.sh /tmp/apply-sslsni-patch.sh
RUN chmod +x /tmp/apply-sslsni-patch.sh && /tmp/apply-sslsni-patch.sh && rm /tmp/apply-sslsni-patch.sh

USER pgadmin
