import React from 'react'
import PropTypes from 'prop-types'
import { Segment } from 'semantic-ui-react'

import Info from 'components/Info'
import { formatDateTime } from 'helpers/dateHelper'
import { dataSourceQueueLogStatuses } from 'helpers/enums'
import ConnectedForm from './ConnectedForm'

const DetailsPage = ({
  info: { id, statId, name, started, ended, status, note, errors, summary },
  logId,
  queueId,
  localize,
}) => (
  <Segment>
    <Info label={localize('Id')} text={id} />
    <Info label={localize('Started')} text={formatDateTime(started)} />
    <Info label={localize('Ended')} text={formatDateTime(ended)} />
    <Info label={localize('StatId')} text={statId} />
    <Info label={localize('Name')} text={name} />
    <Info
      label={localize('Status')}
      text={localize(dataSourceQueueLogStatuses.get(Number(status)))}
    />
    <Info label={localize('Note')} text={localize(note)} />
    {Object.entries(errors).map(([k, v]) => (
      <Info key={k} label={`${localize('ErrorWith')} ${k}`} text={v.map(localize).join('; ')} />
    ))}
    <Info label={localize('Summary')} text={localize(summary)} />
    <ConnectedForm logId={logId} queueId={queueId} />
  </Segment>
)

const { func, shape, oneOfType, string, number } = PropTypes
DetailsPage.propTypes = {
  info: shape({}).isRequired,
  logId: oneOfType([string, number]).isRequired,
  queueId: oneOfType([string, number]).isRequired,
  localize: func.isRequired,
}

export default DetailsPage
