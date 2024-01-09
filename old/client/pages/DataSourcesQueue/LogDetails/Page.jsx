import React from 'react'
import PropTypes from 'prop-types'
import { Container, Grid, Header, Accordion, Segment } from 'semantic-ui-react'

import Info from '/components/Info'
import FormBody from '/components/StatUnitFormBody'
import { formatDateTime } from '/helpers/dateHelper'
import { dataSourceQueueLogStatuses as statuses } from '/helpers/enums'
import connectFormBody from './connectFormBody.js'

const ConnectedForm = connectFormBody(FormBody)

const Page = ({
  info: { statId, name, rawUnit, started, ended, status, note, summary },
  logId,
  queueId,
  localize,
}) => (
  <Container>
    <Grid columns={2} stackable>
      <Grid.Column
        as={Accordion}
        panels={[
          {
            title: { key: 1, content: localize('DataSourceQueueLogInfo'), as: 'h4' },
            content: {
              key: 2,
              content: (
                <Segment>
                  <Info label={localize('Started')} text={formatDateTime(started)} />
                  <Info label={localize('Ended')} text={formatDateTime(ended)} />
                  <Info label={localize('StatId')} text={statId != null ? statId : '-'} />
                  <Info label={localize('Name')} text={name} />
                  <Info label={localize('Status')} text={localize(statuses.get(Number(status)))} />
                  <Info label={localize('Note')} text={note ? localize(note) : '-'} />
                  <Info label={localize('Summary')} text={summary ? localize(summary) : '-'} />
                </Segment>
              ),
            },
          },
        ]}
      />
      <Grid.Column
        as={Accordion}
        panels={[
          {
            title: { key: 1, content: localize('DataSourceQueueLogRawUnit'), as: 'h4' },
            content: {
              key: 2,
              content: (
                <Segment>
                  {Object.entries(rawUnit).map(([k, v]) => (
                    <Info key={k} label={localize(k)} text={v} />
                  ))}
                </Segment>
              ),
            },
          },
        ]}
      />
    </Grid>
    <Header as="h4" content={localize('DataSourceQueueLogUnit')} />
    <ConnectedForm logId={logId} queueId={queueId} showSummary />
  </Container>
)

const { arrayOf, func, shape, oneOfType, string, number } = PropTypes
Page.propTypes = {
  info: shape({
    id: oneOfType([number, string]).isRequired,
    statId: oneOfType([number, string]),
    name: string.isRequired,
    rawUnit: shape({}).isRequired,
    started: string.isRequired,
    ended: string.isRequired,
    status: oneOfType([number, string]).isRequired,
    summary: arrayOf(string).isRequired,
    note: string,
  }).isRequired,
  logId: oneOfType([string, number]).isRequired,
  queueId: oneOfType([string, number]).isRequired,
  localize: func.isRequired,
}

export default Page
