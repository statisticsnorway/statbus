import React from 'react'
import { Button, Form, Search } from 'semantic-ui-react'
import debounce from 'lodash/debounce'

import { dataAccessAttribute as check } from 'helpers/checkPermissions'
import statUnitTypes from 'helpers/statUnitTypes'
import { wrapper } from 'helpers/locale'
import DateField from 'components/fields/DateField'
import { internalRequest } from 'helpers/request'
import styles from './styles'

const { bool, func, number, oneOfType, shape, string } = React.PropTypes

const ActivityCode = ({ 'data-name': name, 'data-code': code }) => (
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
  'data-name': string.isRequired,
  'data-code': string.isRequired,
}
class SearchForm extends React.Component {

  static propTypes = {
    formData: shape({
      wildcard: string,
      type: oneOfType([number, string]),
      includeLiquidated: oneOfType([bool, string]),
      turnoverFrom: string,
      turnoverTo: string,
      employeesNumberFrom: string,
      employeesNumberTo: string,
      lastChangeFrom: string,
      lastChangeTo: string,
      dataSource: string,
      regMainActivityId: string,
      sectorCodeId: string,
      legalFormId: string,
    }).isRequired,
    activityData: shape({
      id: number,
      activityRevy: oneOfType([string, number]),
      activityYear: oneOfType([string, number]),
      activityType: oneOfType([string, number]),
      activityRevxCategory: shape({
        code: string.isRequired,
        name: string.isRequired,
      }),
    }),
    onChange: func.isRequired,
    onSubmit: func.isRequired,
    localize: func.isRequired,
  }

  static defaultProps = {
    formData: {
      wildcard: '',
      type: 0,
      includeLiquidated: false,
      turnoverFrom: '',
      turnoverTo: '',
      employeesNumberFrom: '',
      employeesNumberTo: '',
      dataSource: '',
      regMainActivityId: '',
      sectorCodeId: '',
      legalFormId: '',
    },
    activityData: shape({
      id: 0,
      activityRevy: '',
      activityYear: '',
      activityType: '',
      activityRevxCategory: shape({
        code: '',
        name: '',
      }),
    }),
  }

  state = {
    activityData: this.props.activityData,
    isLoading: false,
    codes: [],
    isOpen: false,
  }

  onCodeChange = (e, value) => {
    this.setState(s => ({
      activityData: {
        ...s.activityData,
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

  codeSelectHandler = (e, result) => {
    this.setState(s => ({
      activityData: {
        ...s.activityData,
        activityRevxCategory: {
          id: result['data-id'],
          code: result['data-code'],
          name: result['data-name'],
        },
      },
    }))
  }

  handleChange = (_, { name, value }) => {
    this.props.onChange(name, value)
  }

  handleChangeCheckbox = (_, { name, checked }) => {
    this.props.onChange(name, checked)
  }

  searchData = debounce(value => internalRequest({
    url: '/api/activities/search',
    method: 'get',
    queryParams: { code: value },
    onSuccess: (resp) => {
      this.setState(s => ({
        activityData: {
          ...s.activityData,
          activityRevxCategory: resp.find(v => v.code === s.activityData.activityRevxCategory.code)
            || s.activityData.activityRevxCategory,
        },
        isLoading: false,
        codes: resp.map(v => ({ title: v.id.toString(), 'data-name': v.name, 'data-code': v.code, 'data-id': v.id })),
      }))
    },
    onFail: () => {
      this.setState({
        isLoading: false,
      })
    },
  }), 250)

  render() {
    const { formData, localize, onSubmit } = this.props

    const defaultType = { value: 'any', text: localize('AnyType') }
    const typeOptions = [
      defaultType,
      ...[...statUnitTypes].map(([key, value]) => ({ value: key, text: localize(value) })),
    ]
    const type = typeOptions[Number(formData.type) || 0].value
    const includeLiquidated = formData.includeLiquidated
      && formData.includeLiquidated.toString().toLowerCase() === 'true'
    const { isLoading, codes, activityData } = this.state

    return (
      <Form onSubmit={onSubmit} className={styles.form}>
        <Form.Input
          name="wildcard"
          value={formData.wildcard}
          onChange={this.handleChange}
          label={localize('SearchWildcard')}
          placeholder={localize('Search')}
          size="large"
        />
        <Form.Select
          name="type"
          value={type}
          onChange={this.handleChange}
          options={typeOptions}
          label={localize('StatisticalUnitType')}
          size="large"
          search
        />
        <Form.Checkbox
          name="includeLiquidated"
          checked={includeLiquidated}
          onChange={this.handleChangeCheckbox}
          label={localize('Includeliquidated')}
        />
        {check('Turnover') && <Form.Input
          name="turnoverFrom"
          value={formData.turnoverFrom}
          onChange={this.handleChange}
          label={localize('TurnoverFrom')}
          type="number"
        />}
        {check('Turnover') && <Form.Input
          name="turnoverTo"
          value={formData.turnoverTo}
          onChange={this.handleChange}
          label={localize('TurnoverTo')}
          type="number"
        />}
        {check('Employees') && <Form.Input
          name="employeesNumberFrom"
          value={formData.employeesNumberFrom}
          onChange={this.handleChange}
          label={localize('NumberOfEmployeesFrom')}
          type="number"
        />}
        {check('Employees') && <Form.Input
          name="employeesNumberTo"
          value={formData.employeesNumberTo}
          onChange={this.handleChange}
          label={localize('NumberOfEmployeesTo')}
          type="number"
        />}
        <DateField
          key="lastChangeFromKey"
          name="lastChangeFrom"
          value={formData.lastChangeFrom || ''}
          onChange={this.handleChange}
          labelKey="LastChangeFrom"
        />
        <DateField
          key="lastChangeToKey"
          name="lastChangeTo"
          value={formData.lastChangeTo || ''}
          onChange={this.handleChange}
          labelKey="LastChangeTo"
        />
        {check('DataSource') && <Form.Input
          name="dataSource"
          value={formData.dataSource}
          onChange={this.handleChange}
          label={localize('DataSource')}
        />}
        <Form.Field
          name="regMainActivityId"
          label={localize('StatUnitActivityRevX')}
          control={Search} loading={isLoading}
          placeholder={localize('StatUnitActivityRevX')}
          onResultSelect={this.codeSelectHandler}
          onSearchChange={this.onCodeChange}
          onChange={this.handleChange}
          results={codes}
          resultRenderer={ActivityCode}
          value={formData.regMainActivityId}

          showNoResults={false}
          fluid
        />
        <Form.Input
          label={localize('Activity')}
          value={activityData.activityRevxCategory.name}
          readOnly
        />
        <Button
          className={styles.sybbtn}
          labelPosition="left"
          icon="search"
          content={localize('Search')}
          type="submit"
          primary
        />
      </Form>
    )
  }
}

export default wrapper(SearchForm)
