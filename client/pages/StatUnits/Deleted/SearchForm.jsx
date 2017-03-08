import React from 'react'
import { Button, Form } from 'semantic-ui-react'

import { dataAccessAttribute as check } from 'helpers/checkPermissions'
import statUnitTypes from 'helpers/statUnitTypes'
import { wrapper } from 'helpers/locale'
import styles from './styles'

const { func, shape, string } = React.PropTypes

class SearchForm extends React.Component {
  static propTypes = {
    query: shape({
      page: string,
      pageSize: string,
    }),
    onChange: func.isRequired,
    localize: func.isRequired,
  }

  static defaultProps = {
    query: {},
  }

  handleChange = (_, { name, value }) => {
    this.props.onChange(name, value)
  }

  handleSubmit = () => {
    this.props.onSubmit()
  }

  render() {
    const { localize, query } = this.props

    const defaultType = { value: 'any', text: localize('AnyType') }
    const typeOptions = [
      defaultType,
      ...[...statUnitTypes].map(([key, value]) => ({ value: key, text: localize(value) })),
    ]

    return (
      <Form onSubmit={this.handleSubmit}>
        <h2>{localize('SearchDeletedStatisticalUnits')}</h2>
        <Form.Input
          name="wildcard"
          label={localize('SearchWildcard')}
          placeholder={localize('Search')}
          size="large"
          onChange={}
          value={query.wildcard || ''}
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
