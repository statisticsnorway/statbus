import React from 'react'
import { shape, func, string, number, oneOfType, object } from 'prop-types'
import { equals } from 'ramda'
import shouldUpdate from 'recompose/shouldUpdate'
import { Grid, Label, Segment, Header } from 'semantic-ui-react'

import { hasValue } from 'helpers/validation'
import { getNewName } from 'helpers/locale'
import styles from './styles.pcss'

const Main = ({ unit, localize, activeTab }) => {
  const selectedActivity = (unit.activities || [])
    .filter(x => x.activityType === 1)
    .sort((a, b) => b.activityType - a.activityType)[0]
  return (
    <div>
      {activeTab !== 'main' && (
        <Header as="h5" className={styles.heigthHeader} content={localize('Main')} />
      )}
      <Segment>
        <Grid container>
          <Grid.Row>
            <Grid.Column width={3}>
              <label className={styles.boldText}>{localize('Status')}</label>
            </Grid.Column>
            <Grid.Column width={5}>
              <Label className={styles.labelStyle} basic size="large">
                {unit && unit.unitStatusId}
              </Label>
            </Grid.Column>
            <Grid.Column width={5} floated="right">
              <div className={styles.container}>
                <label className={styles.boldText}>{localize('TelephoneNo')}</label>
                <Label className={styles.labelStyle} basic size="large">
                  {unit && unit.telephoneNo}
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
                {selectedActivity &&
                  selectedActivity.activityCategory &&
                  selectedActivity.activityCategory.code}
              </Label>
            </Grid.Column>
            <Grid.Column width={10}>
              <Label className={styles.labelStyle} basic size="large">
                {selectedActivity &&
                  hasValue(selectedActivity.activityCategory) &&
                  getNewName(selectedActivity.activityCategory, false)}
              </Label>
            </Grid.Column>
          </Grid.Row>
          <Grid.Row>
            <Grid.Column width={3}>
              <label className={styles.boldText}>{localize('LegalForm')}</label>
            </Grid.Column>
            <Grid.Column width={7}>
              <Label className={styles.labelStyle} basic size="large">
                {unit && hasValue(unit.legalForm) && getNewName(unit.legalForm)}
              </Label>
            </Grid.Column>
          </Grid.Row>
          <Grid.Row>
            <Grid.Column width={3}>
              <label className={styles.boldText}>{localize('InstSectorCode')}</label>
            </Grid.Column>
            <Grid.Column width={8}>
              <Label className={styles.labelStyle} basic size="large">
                {unit && hasValue(unit.instSectorCode) && getNewName(unit.instSectorCode)}
              </Label>
            </Grid.Column>
          </Grid.Row>
          <br />
          <br />
          <br />
          <br />
          <Grid.Row>
            <Grid.Column width={3}>
              <label className={styles.boldText}>{localize('Turnover')}</label>
            </Grid.Column>
            <Grid.Column width={3}>
              <Label className={styles.labelStyle} basic size="large">
                {unit && hasValue(unit.turnover) && unit.turnover >= 0 && unit.turnover}
              </Label>
            </Grid.Column>
            <Grid.Column width={2}>
              <label className={styles.boldText}>{localize('TurnoverYear')}</label>
            </Grid.Column>
            <Grid.Column width={2}>
              <Label className={styles.labelStyle} basic size="large">
                {unit && hasValue(unit.turnoverYear) && unit.turnoverYear >= 0 && unit.turnoverYear}
              </Label>
            </Grid.Column>
          </Grid.Row>
          <Grid.Row>
            <Grid.Column width={3}>
              <label className={styles.boldText}>{localize('Employees')}</label>
            </Grid.Column>
            <Grid.Column width={3}>
              <Label className={styles.labelStyle} basic size="large">
                {unit && hasValue(unit.employees) && unit.employees >= 0 && unit.employees}
              </Label>
            </Grid.Column>
            <Grid.Column width={2}>
              <label className={styles.boldText}>{localize('EmployeesYear')}</label>
            </Grid.Column>
            <Grid.Column width={2}>
              <Label className={styles.labelStyle} basic size="large">
                {unit &&
                  hasValue(unit.employeesYear) &&
                  unit.employeesYear >= 0 &&
                  unit.employeesYear}
              </Label>
            </Grid.Column>
          </Grid.Row>
        </Grid>
      </Segment>
    </div>
  )
}

Main.propTypes = {
  unit: shape({
    unitStatusId: oneOfType([string, number]),
    telephoneNo: oneOfType([string, number]),
    employeesYear: oneOfType([string, number]),
    employees: oneOfType([string, number]),
    turnover: oneOfType([string, number]),
    turnoverYear: oneOfType([string, number]),
    instSectorCode: oneOfType([string, number, object]),
    legalForm: oneOfType([string, number, object]),
  }).isRequired,
  selectedActivity: shape({
    activityCategory: shape({
      code: oneOfType([string, number]).isRequired,
      name: string.isRequired,
    }),
  }),
  localize: func.isRequired,
  activeTab: string.isRequired,
}

export const checkProps = (props, nextProps) =>
  props.localize.lang !== nextProps.localize.lang || !equals(props.unit, nextProps.unit)

export default shouldUpdate(checkProps)(Main)
