import React from 'react'
import { shape, func } from 'prop-types'
import { Grid, Label } from 'semantic-ui-react'

import { hasValue } from 'helpers/validation'
import styles from './styles.pcss'

const BarInfo = ({ unit, localize }) => {
  const sortedActivities = hasValue(unit.activities)
    ? unit.activities.sort((a, b) => b.activityYear - a.activityYear)
    : []
  const lastActivityYear = hasValue(sortedActivities[0]) && sortedActivities[0].activityYear
  const lastActivityByTurnover = sortedActivities.find(x => hasValue(x.turnover))
  const lastActivityByTurnoverYear =
    hasValue(lastActivityByTurnover) && lastActivityByTurnover.activityYear

  return (
    <div>
      <h2>{unit.name}</h2>
      {unit.name === unit.shortName && `(${unit.shortName})`}
      <Grid container columns="equal">
        <Grid.Row>
          {unit.statId !== 0 && (
            <Grid.Column>
              <div className={styles.container}>
                <label className={styles.boldText}>{localize('StatId')}</label>
                <Label className={styles.labelStyle} basic size="large">
                  {unit.statId}
                </Label>
              </div>
            </Grid.Column>
          )}

          {unit.taxRegId !== 0 && (
            <Grid.Column>
              <div className={styles.container}>
                <label className={styles.boldText}>{localize('TaxRegId')}</label>
                <Label className={styles.labelStyle} basic size="large">
                  {unit.taxRegId}
                </Label>
              </div>
            </Grid.Column>
          )}

          {hasValue(unit.externalIdType) &&
            unit.externalIdType !== 0 && (
              <Grid.Column>
                <div className={styles.container}>
                  <label className={styles.boldText}>{localize('ExternalIdType')}</label>
                  <Label className={styles.labelStyle} basic size="large">
                    {unit.externalIdType}
                  </Label>
                </div>
              </Grid.Column>
            )}

          {lastActivityByTurnoverYear !== 0 &&
            lastActivityByTurnoverYear !== false && (
              <Grid.Column>
                <div className={styles.container}>
                  <label className={styles.boldText}>{localize('LastActivityByTurnover')}</label>
                  <Label className={styles.labelStyle} basic size="large">
                    {lastActivityByTurnoverYear}
                  </Label>
                </div>
              </Grid.Column>
            )}

          {lastActivityYear !== 0 && (
            <Grid.Column>
              <div className={styles.container}>
                <label className={styles.boldText}>{localize('NumEmployeeYear')}</label>
                <Label className={styles.labelStyle} basic size="large">
                  {lastActivityYear}{' '}
                </Label>
              </div>
            </Grid.Column>
          )}
        </Grid.Row>
      </Grid>
    </div>
  )
}

BarInfo.propTypes = {
  unit: shape({}).isRequired,
  localize: func.isRequired,
}

export default BarInfo
