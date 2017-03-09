import React from 'react'
import { Button, Form } from 'semantic-ui-react'

import { dataAccessAttribute as check } from 'helpers/checkPermissions'
import statUnitTypes from 'helpers/statUnitTypes'
import { wrapper } from 'helpers/locale'
import styles from './styles'

const { func, shape } = React.PropTypes

class SearchForm extends React.Component {
  static propTypes = {
    formData: shape({}).isRequired,
    onChange: func.isRequired,
    onSubmit: func.isRequired,
    localize: func.isRequired,
  }

  static defaultProps = {
    formData: {
      wildcard: '',
      type: 0,
      includeLiquidated: false,
    },
  }

  handleChange = (_, { name, value }) => {
    this.props.onChange(name, value)
  }

  render() {
    const { localize, formData, onSubmit } = this.props

    const defaultType = { value: 'any', text: localize('AnyType') }
    const typeOptions = [
      defaultType,
      ...[...statUnitTypes].map(([key, value]) => ({ value: key, text: localize(value) })),
    ]

    return (
      <Form onSubmit={onSubmit}>
        <h2>{localize('SearchDeletedStatisticalUnits')}</h2>
        <Form.Input
          name="wildcard"
          value={formData.wildcard || ''}
          onChange={this.handleChange}
          label={localize('SearchWildcard')}
          placeholder={localize('Search')}
          size="large"
        />
        <Form.Select
          name="type"
          value={typeOptions[formData.type || 0].value}
          onChange={this.handleChange}
          label={localize('StatisticalUnitType')}
          options={typeOptions}
          size="large"
          search
        />
        <Form.Checkbox
          name="includeLiquidated"
          checked={formData.includeLiquidated}
          onChange={this.handleChange}
          label={localize('Includeliquidated')}
        />
        {check('Turnover') && <Form.Input
          name="turnoverFrom"
          label={localize('TurnoverFrom')}
          type="number"
          value={formData.turnoverFrom || ''}
        />}
        {check('Turnover') && <Form.Input
          name="turnoverTo"
          label={localize('TurnoverTo')}
          type="number"
          value={formData.turnoverTo || ''}
        />}
        {check('Employees') && <Form.Input
          name="numberOfEmployyesFrom"
          label={localize('NumberOfEmployeesFrom')}
          type="number"
          value={formData.numberOfEmployyesFrom || ''}
        />}
        {check('Employees') && <Form.Input
          name="numberOfEmployyesTo"
          label={localize('NumberOfEmployeesTo')}
          type="number"
          value={formData.numberOfEmployyesTo || ''}
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
