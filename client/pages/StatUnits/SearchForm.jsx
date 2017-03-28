import React from 'react'
import { Button, Form } from 'semantic-ui-react'

import { dataAccessAttribute as check } from 'helpers/checkPermissions'
import statUnitTypes from 'helpers/statUnitTypes'
import { wrapper } from 'helpers/locale'
import styles from './styles'

const { bool, func, number, oneOfType, shape, string } = React.PropTypes
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
    }).isRequired,
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
    },
  }

  handleChange = (_, { name, value }) => {
    this.props.onChange(name, value)
  }

  handleChangeCheckbox = (_, { name, checked }) => {
    this.props.onChange(name, checked)
  }

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
