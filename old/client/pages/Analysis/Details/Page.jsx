import React from 'react'
import PropTypes from 'prop-types'
import { Segment } from 'semantic-ui-react'

import Info from '/components/Info'
import FormBody from '/components/StatUnitFormBody'
import { formatDateTime } from '/helpers/dateHelper'
import { statUnitTypes } from '/helpers/enums'
import connectFormBody from './connectFormBody.js'

const ConnectedForm = connectFormBody(FormBody)

const Page = ({ logId, queueId, logEntry: { unitId, unitType, issuedAt }, localize }) => (
  <Segment>
    <Info label={localize('AnalysisLogId')} text={logId} />
    <Info label={localize('UnitId')} text={unitId} />
    <Info label={localize('UnitType')} text={localize(statUnitTypes.get(unitType))} />
    <Info label={localize('StartDate')} text={formatDateTime(issuedAt)} />
    <ConnectedForm logId={logId} queueId={queueId} showSummary />
  </Segment>
)

Page.propTypes = {
  logId: PropTypes.string.isRequired,
  queueId: PropTypes.string.isRequired,
  logEntry: PropTypes.shape({
    unitId: PropTypes.number.isRequired,
    unitType: PropTypes.number.isRequired,
    issuedAt: PropTypes.string.isRequired,
  }).isRequired,
  localize: PropTypes.func.isRequired,
}

export default Page
