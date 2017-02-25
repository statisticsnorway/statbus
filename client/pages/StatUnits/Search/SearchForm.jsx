import React from 'react'
import R from 'ramda'
import { Button, Form } from 'semantic-ui-react'

import { dataAccessAttribute as check } from 'helpers/checkPermissions'
import statUnitTypes from 'helpers/statUnitTypes'
import { wrapper } from 'helpers/locale'
import defaultQuery from './defaultQuery'
import styles from './styles'

const defaultType = 'any'
const getQuery = fromProps => R.isEmpty(fromProps) ? defaultQuery : fromProps

const { bool, func, number, shape, string } = React.PropTypes

class SearchForm extends React.Component {

  static propTypes = {
    query: shape({
      wildcard: string,
      type: number,
      includeLiquidated: bool,
      turnoverFrom: string,
      turnoverTo: string,
      numberOfEmployyesFrom: string,
      numberOfEmployyesTo: string,
    }),
    search: func.isRequired,
    localize: func.isRequired,
  }

  static defaultProps = {
    query: defaultQuery,
  }

  constructor(props, context) {
    super(props, context)
    this.state = { data: getQuery(this.props.query) }
  }

  componentWillReceiveProps(newProps) {
    this.setState({ data: getQuery(newProps.query) })
  }

  handleEdit = (e, { name, value }) => {
    this.setState(s => ({ data: { ...s.data, [name]: value } }))
  }

  handleSubmit = (e) => {
    e.preventDefault()

    const { data } = this.state
    const queryParams = {
      ...data,
      type: data.type === defaultType
        ? null
        : data.type,
    }
    this.props.search(queryParams)
  }

  render() {
    const { localize } = this.props
    const { data } = this.state

    const toOption = ([key, value]) => ({ value: key, text: localize(value) })
    const typeOptions = [
      { value: defaultType, text: localize('AnyType') },
      ...[...statUnitTypes].map(toOption),
    ]

    return (
      <div className={styles.search}>
        <Form onSubmit={this.handleSubmit} className={styles.form}>
          <h2>{localize('SearchStatisticalUnits')}</h2>
          <Form.Input
            name="wildcard"
            value={data.wildcard}
            onChange={this.handleEdit}
            label={localize('SearchWildcard')}
            placeholder={localize('Search')}
            size="large"
          />
          <Form.Select
            name="type"
            value={typeOptions[data.type].value}
            onChange={this.handleEdit}
            options={typeOptions}
            label={localize('StatisticalUnitType')}
            size="large"
            search
          />
          <Form.Checkbox
            name="includeLiquidated"
            checked={data.includeLiquidated}
            onChange={this.handleEdit}
            label={localize('Includeliquidated')}
          />
          {check('Turnover') && <Form.Input
            name="turnoverFrom"
            value={data.turnoverFrom}
            onChange={this.handleEdit}
            label={localize('TurnoverFrom')}
            type="number"
          />}
          {check('Turnover') && <Form.Input
            name="turnoverTo"
            value={data.turnoverTo}
            onChange={this.handleEdit}
            label={localize('TurnoverTo')}
            type="number"
          />}
          {check('Employees') && <Form.Input
            name="numberOfEmployyesFrom"
            value={data.numberOfEmployyesFrom}
            onChange={this.handleEdit}
            label={localize('NumberOfEmployeesFrom')}
            type="number"
          />}
          {check('Employees') && <Form.Input
            name="numberOfEmployyesTo"
            value={data.numberOfEmployyesTo}
            onChange={this.handleEdit}
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
      </div>
    )
  }
}

export default wrapper(SearchForm)
