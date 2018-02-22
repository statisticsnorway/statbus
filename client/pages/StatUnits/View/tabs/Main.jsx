import React from 'react'
import { shape, func, string } from 'prop-types'
import { equals } from 'ramda'
import shouldUpdate from 'recompose/shouldUpdate'
import { Grid, Label, Segment, Header } from 'semantic-ui-react'
import moment from 'moment'

import { hasValue } from 'helpers/validation'
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
            {unit.statusDate && (
              <Grid.Column width={3}>
                <div className={styles.container}>
                  <label className={styles.boldText}>{localize('StatusDate')}</label>
                  <Label className={styles.labelStyle} basic size="large">
                    {moment(unit.statusDate).format('YYYY/MM/DD')}
                  </Label>
                </div>
              </Grid.Column>
            )}
            {unit.telephoneNo && (
              <Grid.Column width={5}>
                <div className={styles.container}>
                  <label className={styles.boldText}>{localize('TelephoneNo')}</label>
                  <Label className={styles.labelStyle} basic size="large">
                    {unit.telephoneNo}
                  </Label>
                </div>
              </Grid.Column>
            )}
          </Grid.Row>
          {unit.contactPerson && (
            <Grid.Row>
              <Grid.Column floated="right" width={5}>
                <div className={styles.container}>
                  <label className={styles.boldText}>{localize('ContactPerson')}</label>
                  <Label className={styles.labelStyle} basic size="large">
                    {unit.contactPerson}
                  </Label>
                </div>
              </Grid.Column>
            </Grid.Row>
          )}
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
                {selectedActivity && selectedActivity.activityCategory.name}
              </Label>
            </Grid.Column>
          </Grid.Row>
          {unit.legalFormId && (
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
          )}
          {unit.instSectorCodeId && (
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
          <Grid.Row>
            {unit.turnover !== 0 &&
              hasValue(unit.turnover) && (
                <Grid.Column width={3}>
                  <label className={styles.boldText}>{localize('Turnover')}</label>
                </Grid.Column>
              )}
            {unit.turnover !== 0 &&
              hasValue(unit.turnover) && (
                <Grid.Column width={3}>
                  <Label className={styles.labelStyle} basic size="large">
                    {unit.turnover}
                  </Label>
                </Grid.Column>
              )}
            {unit.turnoverYear !== 0 &&
              hasValue(unit.turnoverYear) && (
                <Grid.Column width={2}>
                  <label className={styles.boldText}>{localize('TurnoverYear')}</label>
                </Grid.Column>
              )}
            {unit.turnoverYear !== 0 &&
              hasValue(unit.turnoverYear) && (
                <Grid.Column width={2}>
                  <Label className={styles.labelStyle} basic size="large">
                    {unit.turnoverYear}
                  </Label>
                </Grid.Column>
              )}
            {unit.statIdDate !== 0 &&
              hasValue(unit.statIdDate) && (
                <Grid.Column width={2}>
                  <label className={styles.boldText}>{localize('StatIdDate')}</label>
                </Grid.Column>
              )}
            {unit.statIdDate !== 0 &&
              hasValue(unit.statIdDate) && (
                <Grid.Column width={2}>
                  <Label className={styles.labelStyle} basic size="large">
                    {moment(unit.statIdDate).format('YYYY/MM/DD')}
                  </Label>
                </Grid.Column>
              )}
          </Grid.Row>
          <Grid.Row>
            {unit.employees !== 0 &&
              hasValue(unit.employees) && (
                <Grid.Column width={3}>
                  <label className={styles.boldText}>{localize('Employees')}</label>
                </Grid.Column>
              )}
            {unit.employees !== 0 &&
              hasValue(unit.employees) && (
                <Grid.Column width={3}>
                  <Label className={styles.labelStyle} basic size="large">
                    {unit.employees}
                  </Label>
                </Grid.Column>
              )}
            {unit.employeesYear !== 0 &&
              hasValue(unit.employeesYear) && (
                <Grid.Column width={2}>
                  <label className={styles.boldText}>{localize('EmployeesYear')}</label>
                </Grid.Column>
              )}
            {unit.employeesYear !== 0 &&
              hasValue(unit.employeesYear) && (
                <Grid.Column width={2}>
                  <Label className={styles.labelStyle} basic size="large">
                    {unit.employeesYear}
                  </Label>
                </Grid.Column>
              )}
          </Grid.Row>
        </Grid>
      </Segment>
    </div>
  )
}

Main.propTypes = {
  unit: shape({}).isRequired,
  localize: func.isRequired,
  activeTab: string.isRequired,
}

export const checkProps = (props, nextProps) =>
  props.localize.lang !== nextProps.localize.lang || !equals(props.unit, nextProps.unit)

export default shouldUpdate(checkProps)(Main)
