import React from 'react'
import { shape, number, func, string, oneOfType, bool } from 'prop-types'
import { Button, Table, Form, Popup } from 'semantic-ui-react'
import DatePicker from 'react-datepicker'

import { getDate, toUtc, dateFormat } from 'helpers/dateHelper'
import { activityTypes } from 'helpers/enums'
import SelectField from '../SelectField'

const activities = [...activityTypes].map(([key, value]) => ({ key, value }))
const years = Array.from(new Array(new Date().getFullYear() - 1899), (x, i) => {
  const year = new Date().getFullYear() - i
  return { value: year, text: year }
})

const ActivityCode = ({ 'data-name': name, 'data-code': code }) => (
  <span>
    <strong>{code}</strong>
    &nbsp;
    {name.length > 50 ? (
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
    disabled: bool,
  }

  static defaultProps = {
    disabled: false,
  }

  state = {
    value: this.props.value,
    edited: false,
  }

  onFieldChange = (e, { name, value }) => {
    this.setState(s => ({
      value: { ...s.value, [name]: value },
      edited: true,
    }))
  }

  onDateFieldChange = name => (date) => {
    this.setState(s => ({
      value: { ...s.value, [name]: date === null ? s.value[name] : toUtc(date) },
      edited: true,
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
    this.props.onSave(this.state.value)
  }

  cancelHandler = () => {
    this.props.onCancel(this.state.value.id)
  }

  activitySelectedHandler = (e, result, data) => {
    this.setState(s => ({
      value: {
        ...s.value,
        activityCategoryId: result,
        activityCategory: data,
      },
      edited: true,
    }))
  }

  render() {
    const { localize, disabled } = this.props
    const { value, edited } = this.state
    const employeesIsNaN = isNaN(parseInt(value.employees, 10))
    const turnoverIsNaN = isNaN(parseFloat(value.turnover))
    return (
      <Table.Row>
        <Table.Cell colSpan={8}>
          <Form as="div">
            <Form.Group widths="equal">
              <SelectField
                name="activityCategoryId"
                label="StatUnitActivityRevX"
                lookup={13}
                setFieldValue={this.activitySelectedHandler}
                value={value.activityCategoryId}
                localize={localize}
                required
              />
            </Form.Group>
            <Form.Group widths="equal">
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
              />
              <Popup
                trigger={
                  <Form.Input
                    label={localize('StatUnitActivityEmployeesNumber')}
                    placeholder={localize('StatUnitActivityEmployeesNumber')}
                    type="number"
                    name="employees"
                    value={value.employees}
                    error={employeesIsNaN}
                    onChange={this.onFieldChange}
                    min={0}
                    disabled={disabled}
                    required
                  />
                }
                content={`6 ${localize('MaxLength')}`}
                open={value.employees.length > 6}
              />
            </Form.Group>
            <Form.Group widths="equal">
              <Form.Select
                label={localize('TurnoverYear')}
                placeholder={localize('TurnoverYear')}
                options={years}
                value={value.activityYear}
                error={!value.activityYear}
                name="activityYear"
                onChange={this.onFieldChange}
                disabled={disabled}
                search
              />
              <Popup
                trigger={
                  <Form.Input
                    label={localize('Turnover')}
                    placeholder={localize('Turnover')}
                    name="turnover"
                    type="number"
                    value={value.turnover}
                    error={turnoverIsNaN}
                    onChange={this.onFieldChange}
                    min={0}
                    disabled={disabled}
                    required
                  />
                }
                content={`10 ${localize('MaxLength')}`}
                open={value.turnover.length > 10}
              />
            </Form.Group>
            <Form.Group widths="equal">
              <div className="field datepicker">
                <label htmlFor="idDate">{localize('StatUnitActivityDate')}</label>
                <DatePicker
                  id="idDate"
                  selected={getDate(value.idDate)}
                  value={value.idDate}
                  onChange={this.onDateFieldChange('idDate')}
                  dateFormat={dateFormat}
                  className="ui input"
                  type="number"
                  name="idDate"
                  disabled={disabled}
                />
              </div>
              <div className="field right aligned">
                <label htmlFor="saveBtn">&nbsp;</label>
                <Button.Group>
                  <Popup
                    trigger={
                      <Button
                        id="saveBtn"
                        icon="check"
                        color="green"
                        onClick={this.saveHandler}
                        disabled={
                          disabled ||
                          value.employees.length > 6 ||
                          value.turnover.length > 10 ||
                          !value.activityCategoryId ||
                          !value.activityType ||
                          employeesIsNaN ||
                          !value.activityYear ||
                          turnoverIsNaN ||
                          !value.idDate ||
                          !edited
                        }
                      />
                    }
                    content={localize('ButtonSave')}
                    position="top center"
                  />
                  <Popup
                    trigger={
                      <Button
                        type="button"
                        icon="cancel"
                        color="red"
                        onClick={this.cancelHandler}
                        disabled={disabled}
                      />
                    }
                    content={localize('ButtonCancel')}
                    position="top center"
                  />
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
