import React, { Component, PropTypes } from 'react'
import { Button, Form } from 'semantic-ui-react'

import statUnitTypes from 'helpers/statUnitTypes'
import { wrapper } from 'helpers/locale'
import styles from './styles'

class SearchForm extends Component {
  static propTypes = {
    search: PropTypes.func.isRequired,
  }
  name = 'StatUnitSearchForm'
  render() {
    const { search, localize } = this.props
    const defaultType = { value: 'any', text: 'Any type' }
    const typeOptions = [
      defaultType,
      ...[...statUnitTypes].map(([key, value]) => ({ value: key, text: value })),
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
          />
          <Form.Select
            name="type"
            label={localize('StatisticalUnitType')}
            options={typeOptions}
            defaultValue={typeOptions[0].value}
            size="large"
            search
          />
          <Form.Checkbox
            name="includeLiquidated"
            label={localize('Includeliquidated')}
          />
          <Form.Input
            name="turnoverFrom"
            label={localize('TurnoverFrom')}
            type="number"
          />
          <Form.Input
            name="turnoverTo"
            label={localize('TurnoverTo')}
            type="number"
          />
          <Form.Input
            name="numberOfEmployyesFrom"
            label={localize('NumberOfEmployyesFrom')}
            type="number"
          />
          <Form.Input
            name="numberOfEmployyesTo"
            label={localize('NumberOofEmployyesTo')}
            type="number"
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
      </div>
    )
  }
}

SearchForm.propTypes = { localize: React.PropTypes.func.isRequired }

export default wrapper(SearchForm)
