import React from 'react'
import { shape, number, func, string, oneOfType, bool } from 'prop-types'
import { Button, Table, Form, Popup } from 'semantic-ui-react'
import * as R from 'ramda'
import config from '/helpers/config'
import { activityTypes } from '/helpers/enums'
import { DateTimeField, SelectField } from '/components/fields'
import { getNewName } from 'helpers/locale.js'

const activities = [...activityTypes].map(([key, value]) => ({ key, value }))
// eslint-disable-next-line max-len
const yearsOptions = R.pipe(
  R.range(1900),
  R.reverse,
  R.map(x => ({ value: x, text: x })),
)(new Date().getFullYear())

const ActivityCode = ({ 'data-name': name, 'data-code': code }) => (
  <span>
    <strong>{code}</strong>
    &nbsp;
    {name != null && name.length > 50 ? (
      <span title={name}>{`${name.substring(0, 50)}...`}</span>
    ) : (
      <span>{name}</span>
    )}
  </span>
)

ActivityCode.propTypes = {
  'data-name': string.isRequired,
  'data-code': string.isRequired,
}

class ActivityEdit extends React.Component {
  static propTypes = {
    value: shape({
      id: number,
      activityYear: oneOfType([string, number]),
      activityType: oneOfType([string, number]),
      employees: oneOfType([string, number]),
      turnover: oneOfType([string, number]),
      activityCategoryId: oneOfType([string, number]),
    }).isRequired,
    onSave: func.isRequired,
    onCancel: func.isRequired,
    localize: func.isRequired,
    locale: string.isRequired,
    disabled: bool,
    index: number,
  }

  static defaultProps = {
    disabled: false,
    value: null,
  }

  state = {
    value: this.props.value,
    touched: false,
    index: this.props.index,
  }

  componentWillReceiveProps(nextProps) {
    const { locale } = this.props
    const { value } = this.state
    if (nextProps.locale !== locale) {
      this.setState({
        value: {
          ...value,
          value: value.id,
          label: getNewName(value),
        },
      })
    }
  }

  onFieldChange = (e, { name, value }) => {
    this.setState(s => ({
      value: { ...s.value, [name]: value },
      touched: true,
    }))
  }

  onCodeChange = (e, { value }) => {
    this.setState(s => ({
      value: {
        ...s.value,
        activityCategoryId: {
          id: undefined,
          code: value,
          name: '',
        },
      },
      isLoading: true,
    }))
    this.searchData(value)
  }

  saveHandler = () => {
    this.props.onSave(this.state.value, this.state.index)
  }

  cancelHandler = () => {
    this.props.onCancel(this.state.value.id)
  }

  activitySelectedHandler = (e, { value: activityCategoryId }, activityCategory) => {
    this.setState(s => ({
      value: {
        ...s.value,
        activityCategoryId,
        activityCategory,
      },
      touched: true,
    }))
  }

  render() {
    const { localize, disabled, locale } = this.props
    const { value, touched } = this.state
    // eslint-disable-next-line no-restricted-globals
    const employeesIsNaN = isNaN(parseInt(value.employees, 10))
    const notSelected = { value: 0, text: localize('NotSelected') }
    const activityMandatoryFields = config.mandatoryFields.Activity
    return (
      <Table.Row>
        <Table.Cell colSpan={8}>
          <Form as="div">
            <Form.Group widths="equal">
              <div
                className="field"
                data-tooltip={localize('ActivityCategoryIdTooltip')}
                data-position="top left"
              >
                <SelectField
                  name="activityCategoryId"
                  label="StatUnitActivityRevX"
                  lookup={13}
                  onChange={this.activitySelectedHandler}
                  value={value.activityCategoryId}
                  localize={localize}
                  locale={locale}
                  required={activityMandatoryFields.ActivityCategoryId}
                />
              </div>
            </Form.Group>
            <Form.Group widths="equal">
              <div
                className="field"
                data-tooltip={localize('StatUnitActivityTypeTooltip')}
                data-position="top left"
              >
                <Form.Select
                  label={localize('StatUnitActivityType')}
                  placeholder={localize('StatUnitActivityType')}
                  options={activities.map(a => ({
                    value: a.key,
                    text: localize(a.value),
                  }))}
                  value={value.activityType}
                  error={!value.activityType}
                  name="activityType"
                  onChange={this.onFieldChange}
                  disabled={disabled}
                  required={activityMandatoryFields.ActivityType}
                />
              </div>
              <div
                className="field"
                data-tooltip={localize('ActivityYearTooltip')}
                data-position="top left"
              >
                <Form.Select
                  label={localize('ActivityYear')}
                  placeholder={localize('ActivityYear')}
                  options={[notSelected, ...yearsOptions]}
                  value={value.activityYear}
                  name="activityYear"
                  onChange={this.onFieldChange}
                  disabled={disabled}
                  required={activityMandatoryFields.ActivityYear}
                  search
                />
              </div>
            </Form.Group>
            <Form.Group widths="equal">
              <div
                className="field"
                data-tooltip={localize('StatUnitActivityEmployeesNumberTooltip')}
                data-position="top left"
              >
                <Popup
                  trigger={
                    <Form.Input
                      label={localize('StatUnitActivityEmployeesNumber')}
                      placeholder={localize('StatUnitActivityEmployeesNumber')}
                      type="number"
                      name="employees"
                      value={value.employees}
                      onChange={this.onFieldChange}
                      min={0}
                      required={activityMandatoryFields.Employees}
                      disabled={disabled}
                      autoComplete="off"
                    />
                  }
                  content={`6 ${localize('MaxLength')}`}
                  open={value.employees != null && value.employees.length > 6}
                />
              </div>
              <div
                data-tooltip={localize('InThousandsKGS')}
                data-position="top left"
                className="field"
              >
                <Popup
                  trigger={
                    <Form.Input
                      label={localize('Turnover')}
                      placeholder={localize('Turnover')}
                      name="turnover"
                      type="number"
                      value={value.turnover}
                      onChange={this.onFieldChange}
                      min={0}
                      disabled={disabled}
                      required={activityMandatoryFields.Turnover}
                      autoComplete="off"
                    />
                  }
                  content={`10 ${localize('MaxLength')}`}
                  open={value.turnover != null && value.turnover.length > 10}
                />
              </div>
            </Form.Group>
            <Form.Group widths="equal">
              <div
                className="field"
                data-tooltip={localize('StatUnitActivityDateTooltip')}
                data-position="top left"
              >
                <DateTimeField
                  value={value.idDate}
                  onChange={this.onFieldChange}
                  name="idDate"
                  label="StatUnitActivityDate"
                  disabled={disabled}
                  localize={localize}
                  required={activityMandatoryFields.IdDate}
                />
              </div>
              <div className="field right aligned">
                <label htmlFor="saveBtn">&nbsp;</label>
                <Button.Group>
                  <div data-tooltip={localize('ButtonSave')} data-position="top center">
                    <Button
                      id="saveBtn"
                      icon="check"
                      color="green"
                      onClick={this.saveHandler}
                      disabled={
                        disabled ||
                        (activityMandatoryFields.Employees &&
                          value.employees != null && value.employees.length > 6) ||
                        (value.turnover != null && value.turnover.length > 10) ||
                        (activityMandatoryFields.ActivityCategoryId && !value.activityCategoryId) ||
                        (activityMandatoryFields.ActivityType && !value.activityType) ||
                        (activityMandatoryFields.ActivityYear && !value.activityYear) ||
                        (activityMandatoryFields.Employees && !value.employees && employeesIsNaN) ||
                        (activityMandatoryFields.Turnover && !value.turnover) ||
                        (activityMandatoryFields.IdDate && !value.idDate) ||
                        !touched
                      }
                    />
                  </div>
                  <div data-tooltip={localize('ButtonCancel')} data-position="top center">
                    <Button
                      type="button"
                      icon="cancel"
                      color="red"
                      onClick={this.cancelHandler}
                      disabled={disabled}
                    />
                  </div>
                </Button.Group>
              </div>
            </Form.Group>
          </Form>
        </Table.Cell>
      </Table.Row>
    )
  }
}

export default ActivityEdit
