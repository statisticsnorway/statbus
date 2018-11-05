import React from 'react'
import { shape, func, number, oneOfType, string } from 'prop-types'
import { Grid, Label } from 'semantic-ui-react'

import { hasValue } from 'helpers/validation'
import { statUnitTypes } from '../../../../helpers/enums.js'
import styles from './styles.pcss'

const BarInfo = ({ unit, localize }) => (
  <div>
    <h2>{unit.name}</h2>
    {unit.name === unit.shortName && `(${unit.shortName})`}
    {statUnitTypes.has(unit.unitType) && (
    <h3 className={styles.unitType}>{statUnitTypes.get(unit.unitType)}</h3>
      )}
    <Grid container columns="equal">
      <Grid.Row>
        {hasValue(unit.statId) && (
        <Grid.Column>
          <div className={styles.container}>
            <label className={styles.boldText}>{localize('StatId')}</label>
            <Label className={styles.labelStyle} basic size="large">
              {unit.statId}
            </Label>
          </div>
        </Grid.Column>
          )}

        {hasValue(unit.taxRegId) && (
        <Grid.Column>
          <div className={styles.container}>
            <label className={styles.boldText}>{localize('TaxRegId')}</label>
            <Label className={styles.labelStyle} basic size="large">
              {unit.taxRegId}
            </Label>
          </div>
        </Grid.Column>
          )}

        {hasValue(unit.externalIdType) && (
        <Grid.Column>
          <div className={styles.container}>
            <label className={styles.boldText}>{localize('ExternalIdType')}</label>
            <Label className={styles.labelStyle} basic size="large">
              {unit.externalIdType}
            </Label>
          </div>
        </Grid.Column>
          )}
      </Grid.Row>
    </Grid>
  </div>
)

BarInfo.propTypes = {
  unit: shape({
    statId: oneOfType([string, number]),
    taxRegId: oneOfType([string, number]),
    externalIdType: number,
  }).isRequired,
  localize: func.isRequired,
}

export default BarInfo
