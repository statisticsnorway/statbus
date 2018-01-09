import React from 'react'
import PropTypes from 'prop-types'
import { Segment } from 'semantic-ui-react'

import Info from 'components/Info'
import { formatDateTime } from 'helpers/dateHelper'
import { dataSourceQueueLogStatuses as statuses } from 'helpers/enums'
import ConnectedForm from './ConnectedForm'

const Page = ({
  info: { id, statId, name, started, ended, status, note, summary },
  logId,
  queueId,
  localize,
}) => (
  <Segment>
    <Info label={localize('Id')} text={id} />
    <Info label={localize('Started')} text={formatDateTime(started)} />
    <Info label={localize('Ended')} text={formatDateTime(ended)} />
    <Info label={localize('StatId')} text={statId != null ? statId : '-'} />
    <Info label={localize('Name')} text={name} />
    <Info label={localize('Status')} text={localize(statuses.get(Number(status)))} />
    <Info label={localize('Note')} text={note ? localize(note) : '-'} />
    <Info label={localize('Summary')} text={localize(summary)} />
    <ConnectedForm logId={logId} queueId={queueId} />
  </Segment>
)

const { arrayOf, func, shape, oneOfType, string, number } = PropTypes
Page.propTypes = {
  info: shape({
    id: oneOfType([number, string]).isRequired,
    statId: oneOfType([number, string]),
    name: string.isRequired,
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
