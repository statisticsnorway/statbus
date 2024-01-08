import React from 'react'
import { shape, func, number, oneOfType, string } from 'prop-types'
import { Grid, Label } from 'semantic-ui-react'
import { statUnitTypes } from 'helpers/enums.js'
import styles from './styles.scss'

const BarInfo = ({ unit, localize }) => (
  <div>
    <div style={{ display: 'flex', alignItems: 'center' }}>
      <img
        style={{ width: '25px', marginBottom: '-25px', marginRight: '7px' }}
        src={`icons/${statUnitTypes.get(unit.unitType)}.png`}
        title={localize(statUnitTypes.get(unit.unitType))}
        alt={statUnitTypes.get(unit.unitType)}
      />
      <h2>{unit.name}</h2>
    </div>
    {unit.shortName && unit.shortName.trim() != '' ? (
      <h3 style={{ marginTop: '-1px' }}>({unit.shortName})</h3>
    ) : (
      ''
    )}

    {statUnitTypes.has(unit.unitType) && (
      <h3 className={styles.unitType}>{localize(statUnitTypes.get(unit.unitType))}</h3>
    )}
    <Grid container columns="equal">
      <Grid.Row>
        <Grid.Column>
          <div className={styles.container}>
            <label className={styles.boldText}>{localize('StatId')}</label>
            <Label
              className={styles[`${unit && unit.statId ? 'labelStyle' : 'emptyLabel'}`]}
              basic
              size="large"
            >
              {unit.statId}
            </Label>
          </div>
        </Grid.Column>

        <Grid.Column>
          <div className={styles.container}>
            <label className={styles.boldText}>{localize('TaxRegId')}</label>
            <Label
              className={styles[`${unit && unit.taxRegId ? 'labelStyle' : 'emptyLabel'}`]}
              basic
              size="large"
            >
              {unit.taxRegId}
            </Label>
          </div>
        </Grid.Column>

        <Grid.Column>
          <div className={styles.container}>
            <label className={styles.boldText}>{localize('ExternalIdType')}</label>
            <Label
              className={styles[`${unit && unit.externalIdType ? 'labelStyle' : 'emptyLabel'}`]}
              basic
              size="large"
            >
              {unit.externalIdType}
            </Label>
          </div>
        </Grid.Column>
      </Grid.Row>
    </Grid>
  </div>
)

BarInfo.propTypes = {
  unit: shape({
    statId: oneOfType([string, number]),
    taxRegId: oneOfType([string, number]),
    externalIdType: string,
  }).isRequired,
  localize: func.isRequired,
}

export default BarInfo
