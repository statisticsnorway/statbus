import React from 'react'
import { Button, Table, Form, Search } from 'semantic-ui-react'

import DatePicker from 'components/fields/DateField'
import { wrapper } from 'helpers/locale'
import { internalRequest } from 'helpers/request'
import activityTypes from './activityTypes'

const activities = [...activityTypes.entries()].map(([key, value]) => ({ key, value }))
const years = Array.from(new Array(new Date().getFullYear() - 1899), (x, i) => {
  const year = new Date().getFullYear() - i
  return { value: year, text: year }
})

const { shape, number, func, string, oneOfType } = React.PropTypes

const ActivityCode = ({ code, name }) => (
  <span>
    <strong>{code}</strong>
    &nbsp;
    {name.length > 50
      ? <span title={name}>{`${name.substring(0, 50)}...`}</span>
      : <span>{name}</span>
    }

  </span>
)

ActivityCode.propTypes = {
  code: string.isRequired,
  name: string.isRequired,
}

const validators = {

}

class ActivityEdit extends React.Component {
  static propTypes = {
    data: shape({
      id: number,
      activityRevx: oneOfType([string, number]),
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
  }

  state = {
    data: this.props.data,
    isLoading: false,
    codes: [],
  }

  onFieldChange = (e, { name, value }) => {
    this.setState(s => ({
      data: { ...s.data, [name]: value },
    }))
  }

  onCodeChange = (e, value) => {
    this.setState(s => ({
      data: {
        ...s.data,
        activityRevxCategory: {
          code: value,
          name: '',
        },
      },
      isLoading: true,
    }))

    internalRequest({
      url: '/api/activities/search',
      method: 'get',
      queryParams: { code: value },
      onSuccess: (resp) => {
        this.setState(s => ({
          data: {
            ...s.data,
            activityRevxCategory: resp.find(v => v.code === s.data.activityRevxCategory.code) || s.data.activityRevxCategory,
          },
          isLoading: false,
          codes: resp,
        }))
      },
      onFail: () => {
        this.setState(s => ({
          isLoading: false,
        }))
      },
    })
  }

  codeSelectHandler = (e, result) => {
    this.setState(s => ({
      data: {
        ...s.data,
        activityRevxCategory: result,
      },
    }))
  }

  saveHandler = () => {
    const { onSave } = this.props
    onSave(this.state.data)
  }

  cancelHandler = () => {
    const { onCancel } = this.props
    onCancel(this.state.data.id)
  }

  render() {
    const { data, isLoading, codes } = this.state
    const { localize } = this.props
    return (
      <Table.Row>
        <Table.Cell colSpan={8}>
          <Form as="div">
            <Form.Group widths="equal">
              <Form.Field
                label={localize('StatUnitActivityRevX')}
                control={Search} loading={isLoading}
                placeholder={localize('StatUnitActivityRevX')}
                onResultSelect={this.codeSelectHandler}
                onSearchChange={this.onCodeChange}
                results={codes}
                resultRenderer={ActivityCode}
                value={data.activityRevxCategory.code}
                error={!data.activityRevxCategory.code}
                required
                showNoResults={false}
                fluid
              />
              <Form.Input
                label={localize('Activity')}
                value={data.activityRevxCategory.name}
                readOnly
              />
            </Form.Group>
            <Form.Group widths="equal">
              <Form.Select
                label={localize('StatUnitActivityType')}
                placeholder={localize('StatUnitActivityType')}
                options={activities.map(({ key, value }) => ({ value: key, text: localize(value) }))}
                value={data.activityType}
                error={!data.activityType}
                name="activityType"
                onChange={this.onFieldChange}
              />
              <Form.Input
                label={localize('StatUnitActivityEmployeesNumber')}
                placeholder={localize('StatUnitActivityEmployeesNumber')}
                type="number"
                name="employees"
                value={data.employees}
                error={isNaN(parseInt(data.employees))}
                onChange={this.onFieldChange}
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
                search
              />
              <Form.Input
                label={localize('Turnover')}
                placeholder={localize('Turnover')}
                name="turnover"
                type="number"
                value={data.turnover}
                error={isNaN(parseFloat(data.turnover))}
                onChange={this.onFieldChange}
              />
            </Form.Group>
            <Form.Group widths="equal">
              <DatePicker
                labelKey="StatUnitActivityDate"
                type="number"
                name="idDate"
                value={data.idDate}
                error={!data.idDate}
                onChange={this.onFieldChange}
              />
              <div className="field right aligned">
                <label>&nbsp;</label>
                <Button.Group>
                  <Button
                    icon="check"
                    color="green"
                    onClick={this.saveHandler}
                    disabled={
                      !data.activityRevxCategory.code ||
                      !data.activityType ||
                      isNaN(parseInt(data.employees)) ||
                      !data.activityYear ||
                      isNaN(parseFloat(data.turnover)) ||
                      !data.idDate
                    }
                  />
                  <Button icon="cancel" color="red" onClick={this.cancelHandler} />
                </Button.Group>
              </div>
            </Form.Group>
          </Form>
        </Table.Cell>
      </Table.Row>
    )
  }
}

export default wrapper(ActivityEdit)

