import React from 'react'
import { shape, func } from 'prop-types'
import { equals } from 'ramda'
import shouldUpdate from 'recompose/shouldUpdate'
import { Grid, Label } from 'semantic-ui-react'

import styles from './styles.pcss'

const Main = ({ unit, localize }) => {
  const selectedActivity = unit.activities
    .filter(x => x.activityType === 1)
    .sort((a, b) => b.activityType - a.activityType)[0]
  return (
    <Grid container>
      <Grid.Row>
        <Grid.Column width={3}>
          <label className={styles.boldText}>{localize('Status')}</label>
        </Grid.Column>
        <Grid.Column width={3}>
          <Label className={styles.labelStyle} basic size="large">
            {unit.status}
          </Label>
        </Grid.Column>
        <Grid.Column floated="right" width={4}>
          <div className={styles.container}>
            <label className={styles.boldText}>{localize('TelephoneNo')}</label>
            <Label className={styles.labelStyle} basic size="large">
              {unit.telephoneNo}
            </Label>
          </div>
        </Grid.Column>
      </Grid.Row>

      <Grid.Row>
        <Grid.Column width={3}>
          <label className={styles.boldText}>{localize('PrimaryActivity')}</label>
        </Grid.Column>
        <Grid.Column width={3}>
          <Label className={styles.labelStyle} basic size="large">
            {selectedActivity.activityCategory.code}
          </Label>
        </Grid.Column>
        <Grid.Column width={10}>
          <Label className={styles.labelStyle} basic size="large">
            {selectedActivity.activityCategory.name}
          </Label>
        </Grid.Column>
      </Grid.Row>

      <Grid.Row>
        <Grid.Column width={3}>
          <label className={styles.boldText}>{localize('LegalForm')}</label>
        </Grid.Column>
        <Grid.Column width={6}>
          <Label className={styles.labelStyle} basic size="large">
            {unit.legalFormId}
          </Label>
        </Grid.Column>
      </Grid.Row>

      <Grid.Row>
        <Grid.Column width={3}>
          <label className={styles.boldText}>{localize('InstSectorCode')}</label>
        </Grid.Column>
        <Grid.Column width={8}>
          <Label className={styles.labelStyle} basic size="large">
            {unit.instSectorCodeId}
          </Label>
        </Grid.Column>
      </Grid.Row>
      <br />
      <br />
      <br />
      <br />
      <br />
      <Grid.Row>
        <Grid.Column width={2}>
          <label className={styles.boldText}>{localize('Turnover')}</label>
        </Grid.Column>
        <Grid.Column width={2}>
          <Label className={styles.labelStyle} basic size="large">
            {unit.turnover}
          </Label>
        </Grid.Column>
        <Grid.Column width={1}>
          <label className={styles.boldText}>{localize('year')}</label>
        </Grid.Column>
        <Grid.Column width={2}>
          <Label className={styles.labelStyle} basic size="large">
            {unit.turnoverYear}
          </Label>
        </Grid.Column>
      </Grid.Row>

      <Grid.Row>
        <Grid.Column width={2}>
          <label className={styles.boldText}>{localize('NumOfEmployees')}</label>
        </Grid.Column>
        <Grid.Column width={2}>
          <Label className={styles.labelStyle} basic size="large">
            {unit.employees}
          </Label>
        </Grid.Column>
        <Grid.Column width={1}>
          <label className={styles.boldText}>{localize('year')}</label>
        </Grid.Column>
        <Grid.Column width={2}>
          <Label className={styles.labelStyle} basic size="large">
            {unit.employeesYear}
          </Label>
        </Grid.Column>
      </Grid.Row>
    </Grid>
  )
}

Main.propTypes = {
  unit: shape({}),
  localize: func.isRequired,
}

Main.defaultProps = {
  unit: undefined,
}

export const checkProps = (props, nextProps) =>
  props.localize.lang !== nextProps.localize.lang || !equals(props.unit, nextProps.unit)

export default shouldUpdate(checkProps)(Main)
