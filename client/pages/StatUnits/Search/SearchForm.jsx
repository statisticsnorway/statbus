import React, { Component, PropTypes } from 'react'
import { Button, Form } from 'semantic-ui-react'

import { dataAccessAttribute as check } from 'helpers/checkPermissions'
import statUnitTypes from 'helpers/statUnitTypes'
import { wrapper } from 'helpers/locale'
import styles from './styles'

class SearchForm extends Component {
  static propTypes = {
    search: PropTypes.func.isRequired,
  }
  name = 'StatUnitSearchForm'

  render() {
    const { search, localize, query } = this.props
    const defaultType = { value: 'any', text: localize('AnyType') }
    const typeOptions = [
      defaultType,
      ...[...statUnitTypes].map(([key, value]) => ({ value: key, text: localize(value) })),
    ]
    const handleSubmit = (e, { formData }) => {
      e.preventDefault()
      const queryParams = {
        ...formData,
        type: formData.type === defaultType.value
          ? null
          : formData.type,
      }
      search(queryParams)
    }
    return (
      <div className={styles.search}>
        <Form className={styles.form} onSubmit={handleSubmit}>
          <h2>{localize('SearchStatisticalUnits')}</h2>
          <Form.Input
            name="wildcard"
            label={localize('SearchWildcard')}
            placeholder={localize('Search')}
            size="large"
            defaultValue={query.wildcard || ''}
          />
          <Form.Select
            name="type"
            label={localize('StatisticalUnitType')}
            options={typeOptions}
            size="large"
            search
            defaultValue={typeOptions[query.type || 0].value}
          />
          <Form.Checkbox
            name="includeLiquidated"
            label={localize('Includeliquidated')}
            defaultChecked={query.includeLiquidated}
          />
          {check('Turnover') && <Form.Input
            name="turnoverFrom"
            label={localize('TurnoverFrom')}
            type="number"
            defaultValue={query.turnoverFrom || ''}
          />}
          {check('Turnover') && <Form.Input
            name="turnoverTo"
            label={localize('TurnoverTo')}
            type="number"
            defaultValue={query.turnoverTo || ''}
          />}
          {check('Employees') && <Form.Input
            name="numberOfEmployyesFrom"
            label={localize('NumberOfEmployeesFrom')}
            type="number"
            defaultValue={query.numberOfEmployyesFrom || ''}
          />}
          {check('Employees') && <Form.Input
            name="numberOfEmployyesTo"
            label={localize('NumberOfEmployeesTo')}
            type="number"
            defaultValue={query.numberOfEmployyesTo || ''}
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
      </div>
    )
  }
}

SearchForm.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(SearchForm)
