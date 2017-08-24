import React from 'react'
import { shape, number, func, string, oneOfType, bool } from 'prop-types'
import { Button, Table, Form, Search, Popup } from 'semantic-ui-react'
import DatePicker from 'react-datepicker'
import debounce from 'lodash/debounce'

import { getDate, toUtc, dateFormat } from 'helpers/dateHelper'
import { activityTypes } from 'helpers/enums'
import { internalRequest } from 'helpers/request'

const activities = [...activityTypes].map(([key, value]) => ({ key, value }))
const years = Array.from(new Array(new Date().getFullYear() - 1899), (x, i) => {
  const year = new Date().getFullYear() - i
  return { value: year, text: year }
})

const ActivityCode = ({ 'data-name': name, 'data-code': code }) => (
  <span>
    <strong>{code}</strong>
    &nbsp;
    {name.length > 50
      ? <span title={name}>{`${name.substring(0, 50)}...`}</span>
      : <span>{name}</span>}
  </span>
)

ActivityCode.propTypes = {
  'data-name': string.isRequired,
  'data-code': string.isRequired,
}

class ActivityEdit extends React.Component {
  static propTypes = {
    data: shape({
      id: number,
      activityRevy: oneOfType([string, number]),
      activityYear: oneOfType([string, number]),
      activityType: oneOfType([string, number]),
      employees: oneOfType([string, number]),
      turnover: oneOfType([string, number]),
      activityRevxCategory: shape({
        code: string.isRequired,
        name: string.isRequired,
      }),
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
    data: this.props.data,
    isLoading: false,
    codes: [],
    isOpen: false,
  }

  onFieldChange = (e, { name, value }) => {
    this.setState(s => ({
      data: { ...s.data, [name]: value },
    }))
  }

  onDateFieldChange = name => (date) => {
    this.setState(s => ({
      data: { ...s.data, [name]: date === null ? s.data[name] : toUtc(date) },
    }))
  }

  onCodeChange = (e, { value }) => {
    this.setState(s => ({
      data: {
        ...s.data,
        activityRevxCategory: {
          id: undefined,
          code: value,
          name: '',
        },
      },
      isLoading: true,
    }))
    this.searchData(value)
  }

  searchData = debounce(value => internalRequest({
    url: '/api/activities/search',
    method: 'get',
    queryParams: { wildcard: value },
    onSuccess: (resp) => {
      this.setState(s => ({
        data: {
          ...s.data,
          activityRevxCategory: resp.find(v => v.code === s.data.activityRevxCategory.code)
            || s.data.activityRevxCategory,
        },
        isLoading: false,
        codes: resp.map(v => ({
          title: v.id.toString(),
          'data-name': v.name,
          'data-code': v.code,
          'data-id': v.id,
        })),
      }))
    },
    onFail: () => {
      this.setState({
        isLoading: false,
      })
    },
  }), 250)

  codeSelectHandler = (e, { result }) => {
    this.setState(s => ({
      data: {
        ...s.data,
        activityRevxCategory: {
          id: result['data-id'],
          code: result['data-code'],
          name: result['data-name'],
        },
      },
    }))
  }

  saveHandler = () => {
    this.props.onSave(this.state.data)
  }

  cancelHandler = () => {
    this.props.onCancel(this.state.data.id)
  }

  handleOpen = () => {
    this.setState({ isOpen: true })
  }

  render() {
    const { localize, disabled } = this.props
    const { data, isLoading, codes } = this.state
    return (
      <Table.Row>
        <Table.Cell colSpan={8}>
          <Form as="div">
            <Form.Group widths="equal">
              <Form.Field
                label={localize('StatUnitActivityRevX')}
                control={Search}
                loading={isLoading}
                placeholder={localize('StatUnitActivityRevX')}
                onResultSelect={this.codeSelectHandler}
                onSearchChange={this.onCodeChange}
                results={codes}
                resultRenderer={ActivityCode}
                value={data.activityRevxCategory.code}
                error={!data.activityRevxCategory.code}
                disabled={disabled}
                showNoResults={false}
                required
                fluid
              />
              <Form.Input
                label={localize('Activity')}
                value={data.activityRevxCategory.name}
                disabled={disabled}
                readOnly
              />
            </Form.Group>
            <Form.Group widths="equal">
              <Form.Select
                label={localize('StatUnitActivityType')}
                placeholder={localize('StatUnitActivityType')}
                options={activities.map(a => ({ value: a.key, text: localize(a.value) }))}
                value={data.activityType}
                error={!data.activityType}
                name="activityType"
                onChange={this.onFieldChange}
                disabled={disabled}
              />
              <Popup
                trigger={(
                  <Form.Input
                    label={localize('StatUnitActivityEmployeesNumber')}
                    placeholder={localize('StatUnitActivityEmployeesNumber')}
                    type="number"
                    name="employees"
                    value={data.employees}
                    error={isNaN(parseInt(data.employees, 10))}
                    onChange={this.onFieldChange}
                    min={0}
                    disabled={disabled}
                  />
                )}
                content={`6 ${localize('MaxLength')}`}
                open={data.employees.length > 6}
                onOpen={this.handleOpen}
              />
            </Form.Group>
            <Form.Group widths="equal">
              <Form.Select
                label={localize('TurnoverYear')}
                placeholder={localize('TurnoverYear')}
                options={years}
                value={data.activityYear}
                error={!data.activityYear}
                name="activityYear"
                onChange={this.onFieldChange}
                disabled={disabled}
                search
              />
              <Popup
                trigger={(
                  <Form.Input
                    label={localize('Turnover')}
                    placeholder={localize('Turnover')}
                    name="turnover"
                    type="number"
                    value={data.turnover}
                    error={isNaN(parseFloat(data.turnover))}
                    onChange={this.onFieldChange}
                    min={0}
                    disabled={disabled}
                  />
                )}
                content={`10 ${localize('MaxLength')}`}
                open={data.turnover.length > 10}
                onOpen={this.handleOpen}
              />
            </Form.Group>
            <Form.Group widths="equal">
              <div className="field datepicker">
                <label htmlFor="idDate">{localize('StatUnitActivityDate')}</label>
                <DatePicker
                  id="idDate"
                  selected={getDate(data.idDate)}
                  value={data.idDate}
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
                  <Button
                    id="saveBtn"
                    icon="check"
                    color="green"
                    onClick={this.saveHandler}
                    disabled={
                      disabled ||
                      data.employees.length > 6 ||
                      data.turnover.length > 10 ||
                      !data.activityRevxCategory.code ||
                      !data.activityType ||
                      isNaN(parseInt(data.employees, 10)) ||
                      !data.activityYear ||
                      isNaN(parseFloat(data.turnover)) ||
                      !data.idDate}
                  />
                  <Button icon="cancel" color="red" onClick={this.cancelHandler} disabled={disabled} />
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
