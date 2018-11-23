import React from 'react'
import { shape, func, string, number, oneOfType } from 'prop-types'
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
          {(unit && unit.unitStatusId) || unit.telephoneNo ? (
            <Grid.Row>
              {unit.unitStatusId && (
                <Grid.Column width={3}>
                  <label className={styles.boldText}>{localize('Status')}</label>
                </Grid.Column>
              )}
              {unit.unitStatusId && (
                <Grid.Column width={5}>
                  <Label className={styles.labelStyle} basic size="large">
                    {unit.unitStatusId}
                  </Label>
                </Grid.Column>
              )}
              {unit.telephoneNo && (
                <Grid.Column width={5} floated="right">
                  <div className={styles.container}>
                    <label className={styles.boldText}>{localize('TelephoneNo')}</label>
                    <Label className={styles.labelStyle} basic size="large">
                      {unit.telephoneNo}
                    </Label>
                  </div>
                </Grid.Column>
              )}
            </Grid.Row>
          ) : null}
          {selectedActivity && (
            <Grid.Row>
              <Grid.Column width={3}>
                <label className={styles.boldText}>{localize('PrimaryActivity')}</label>
              </Grid.Column>
              <Grid.Column width={3}>
                <Label className={styles.labelStyle} basic size="large">
                  {selectedActivity && selectedActivity.activityCategory.code}
                </Label>
              </Grid.Column>
              <Grid.Column width={10}>
                <Label className={styles.labelStyle} basic size="large">
                  {selectedActivity && getNewName(selectedActivity.activityCategory)}
                </Label>
              </Grid.Column>
            </Grid.Row>
          )}
          {unit &&
            unit.legalFormId && (
              <Grid.Row>
                <Grid.Column width={3}>
                  <label className={styles.boldText}>{localize('LegalForm')}</label>
                </Grid.Column>
                <Grid.Column width={7}>
                  <Label className={styles.labelStyle} basic size="large">
                    {unit.legalFormId}
                  </Label>
                </Grid.Column>
              </Grid.Row>
            )}
          {unit &&
            unit.instSectorCodeId && (
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
            )}
          <br />
          <br />
          <br />
          <br />
          {(unit && unit.turnover) || unit.turnoverYear ? (
            <Grid.Row>
              {unit.turnover >= 0 &&
                hasValue(unit.turnover) && (
                  <Grid.Column width={3}>
                    <label className={styles.boldText}>{localize('Turnover')}</label>
                  </Grid.Column>
                )}
              {unit.turnover >= 0 &&
                hasValue(unit.turnover) && (
                  <Grid.Column width={3}>
                    <Label className={styles.labelStyle} basic size="large">
                      {unit.turnover}
                    </Label>
                  </Grid.Column>
                )}
              {unit.turnoverYear >= 0 &&
                hasValue(unit.turnoverYear) && (
                  <Grid.Column width={2}>
                    <label className={styles.boldText}>{localize('TurnoverYear')}</label>
                  </Grid.Column>
                )}
              {unit.turnoverYear >= 0 &&
                hasValue(unit.turnoverYear) && (
                  <Grid.Column width={2}>
                    <Label className={styles.labelStyle} basic size="large">
                      {unit.turnoverYear}
                    </Label>
                  </Grid.Column>
                )}
            </Grid.Row>
          ) : null}
          {(unit && unit.employees) || unit.employeesYear ? (
            <Grid.Row>
              {unit.employees >= 0 &&
                hasValue(unit.employees) && (
                  <Grid.Column width={3}>
                    <label className={styles.boldText}>{localize('Employees')}</label>
                  </Grid.Column>
                )}
              {unit.employees >= 0 &&
                hasValue(unit.employees) && (
                  <Grid.Column width={3}>
                    <Label className={styles.labelStyle} basic size="large">
                      {unit.employees}
                    </Label>
                  </Grid.Column>
                )}
              {unit.employeesYear >= 0 &&
                hasValue(unit.employeesYear) && (
                  <Grid.Column width={2}>
                    <label className={styles.boldText}>{localize('EmployeesYear')}</label>
                  </Grid.Column>
                )}
              {unit.employeesYear >= 0 &&
                hasValue(unit.employeesYear) && (
                  <Grid.Column width={2}>
                    <Label className={styles.labelStyle} basic size="large">
                      {unit.employeesYear}
                    </Label>
                  </Grid.Column>
                )}
            </Grid.Row>
          ) : null}
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
    instSectorCodeId: oneOfType([string, number]),
    legalFormId: oneOfType([string, number]),
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
