import React from 'react'
import { shape, func } from 'prop-types'
import { equals } from 'ramda'
import shouldUpdate from 'recompose/shouldUpdate'
import { Grid, Label, Segment } from 'semantic-ui-react'

import { formatDateTime as parseFormat } from 'helpers/dateHelper'

const fields = [
  { name: 'regId', label: 'RegId' },
  { name: 'regIdDate', label: 'RegIdDate', getValue: parseFormat },
  { name: 'externalId', label: 'ExternalId' },
  { name: 'externalIdDate', label: 'ExternalIdDate', getValue: parseFormat },
  { name: 'refNo', label: 'RefNo' },
  { name: 'postalAddressId', label: 'PostalAddressId' },
  { name: 'regMainActivity', label: 'RegMainActivity' },
  { name: 'registrationDate', label: 'RegistrationDate' },
  { name: 'registrationReason', label: 'RegistrationReason' },
  { name: 'liqDate', label: 'LiqDate' },
  { name: 'liqReason', label: 'LiqReason' },
  { name: 'suspensionStart', label: 'SuspensionStart' },
  { name: 'suspensionEnd', label: 'SuspensionEnd' },
  { name: 'reorgTypeCode', label: 'ReorgTypeCode' },
  { name: 'reorgDate', label: 'ReorgDate', getValue: parseFormat },
  { name: 'reorgReferences', label: 'ReorgReferences' },
  { name: 'contactPerson', label: 'ContactPerson' },
  { name: 'status', label: 'Status' },
  { name: 'statusDate', label: 'StatusDate', getValue: parseFormat },
  { name: 'freeEconZone', label: 'FreeEconZone' },
  { name: 'foreignParticipationCountryId', label: 'ForeignParticipationCountryId' },
  { name: 'foreignParticipation', label: 'ForeignParticipation' },
  { name: 'classified', label: 'Classified' },
  { name: 'isDeleted', label: 'IsDeleted' },
  { name: 'entGroupIdDate', label: 'EntGroupIdDate', getValue: parseFormat },
  { name: 'commercial', label: 'Commercial' },
  { name: 'instSectorCode', label: 'InstSectorCode' },
  { name: 'totalCapital', label: 'TotalCapital' },
  { name: 'munCapitalShare', label: 'MunCapitalShare' },
  { name: 'stateCapitalShare', label: 'StateCapitalShare' },
  { name: 'privCapitalShare', label: 'PrivCapitalShare' },
  { name: 'foreignCapitalShare', label: 'ForeignCapitalShare' },
  { name: 'foreignCapitalCurrency', label: 'ForeignCapitalCurrency' },
  { name: 'entGroupRole', label: 'EntGroupRole' },
  { name: 'entRegIdDate', label: 'EntRegIdDate' },
  { name: 'founders', label: 'Founders' },
  { name: 'owner', label: 'Owner' },
  { name: 'market', label: 'Market' },
  { name: 'legalForm', label: 'LegalForm' },
  { name: 'instSectorCode', label: 'InstSectorCode' },
  { name: 'totalCapital', label: 'TotalCapital' },
  { name: 'munCapitalShare', label: 'MunCapitalShare' },
  { name: 'stateCapitalShare', label: 'StateCapitalShare' },
  { name: 'privCapitalShare', label: 'PrivCapitalShare' },
  { name: 'foreignCapitalShare', label: 'ForeignCapitalShare' },
  { name: 'foreignCapitalCurrency', label: 'ForeignCapitalCurrency' },
  { name: 'notes', label: 'Notes' },
  { name: 'legalUnitIdDate', label: 'LegalUnitIdDate', getValue: parseFormat },
  { name: 'dataSource', label: 'DataSource' },
]

const Main = ({ unit, localize }) => (
  <Grid container columns={2}>
    {fields.map(x => unit[x.name] &&
      <Grid.Column key={x.name}>
        <Segment size="mini">
          <Label content={localize(x.label)} pointing="right" size="small" />
          {x.getValue ? x.getValue(unit[x.name]) : unit[x.name]}
        </Segment>
      </Grid.Column>)}
  </Grid>
)

Main.propTypes = {
  unit: shape({}),
  localize: func.isRequired,
}

Main.defaultProps = {
  unit: undefined,
}

export const checkProps = (props, nextProps) =>
  props.localize.lang !== nextProps.localize.lang
  || !equals(props.unit, nextProps.unit)

export default shouldUpdate(checkProps)(Main)
