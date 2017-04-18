import React from 'react'
import { Segment, Table } from 'semantic-ui-react'
import R from 'ramda'

import { systemFunction as sF } from 'helpers/checkPermissions'
import { wrapper } from 'helpers/locale'
import { getDate, formatDate } from 'helpers/dateHelper'
import Paginate from 'components/Paginate'
import styles from './styles'
import DataSourceQueueItem from './DataSourceQueueItem'
import SearchForm from './SearchForm'


const { func, array, bool, shape, number, string } = React.PropTypes

class ViewDataSourceQueues extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    result: array.isRequired,
    totalCount: number.isRequired,
    actions: shape({
      updateFilter: func.isRequired,
      setQuery: func.isRequired,
      fetchData: func.isRequired,
    }).isRequired,
    fetching: bool.isRequired,
    formData: shape({}).isRequired,
    query: shape({
      status: string,
      dateTo: string,
    }),
  }

  static defaultProps = {
    query: {
      status: 'any',
      dateTo: formatDate(getDate()),
    },
  }

  componentDidMount() {
    this.props.actions.fetchData(this.props.query)
  }

  componentWillReceiveProps(nextProps) {
    if (!R.equals(nextProps.query, this.props.query)) {
      nextProps.actions.fetchData(nextProps.query)
    }
  }
  shouldComponentUpdate(nextProps, nextState) {
    return this.props.localize.lang !== nextProps.localize.lang
      || !R.equals(this.props, nextProps)
      || !R.equals(this.state, nextState)
  }

  handleChangeForm = (name, value) => {
    this.props.actions.updateFilter({ [name]: value })
  }

  handleSubmitForm = (e) => {
    e.preventDefault()
    const { actions: { setQuery }, query, formData } = this.props
    setQuery({ ...query, ...formData })
  }

  renderRow = item => (
    <DataSourceQueueItem
      data={item}
      key={item.id}
      localize={this.props.localize}
    />
   )

  render() {
    const { result, localize, fetching, totalCount, formData } = this.props
    return (
      <div>
        <h2>{localize('DataSourceQueues')}</h2>
        <Segment loading={fetching}>
          <SearchForm
            searchQuery={formData}
            onChange={this.handleChangeForm}
            onSubmit={this.handleSubmitForm}
          />
          <br />
          <Paginate totalCount={Number(totalCount)}>
            <Table selectable size="small" className={styles.wrap}>
              <Table.Header>
                <Table.Row>
                  <Table.HeaderCell>{localize('DataSourceName')}</Table.HeaderCell>
                  <Table.HeaderCell>{localize('DataSourceTemplateName')}</Table.HeaderCell>
                  <Table.HeaderCell>{localize('UploadDateTime')}</Table.HeaderCell>
                  <Table.HeaderCell>{localize('UserName')}</Table.HeaderCell>
                  <Table.HeaderCell>{localize('Status')}</Table.HeaderCell>
                </Table.Row>
              </Table.Header>
              <Table.Body>
                {result.map(this.renderRow)}
              </Table.Body>
            </Table>
          </Paginate>
        </Segment>
      </div>
    )
  }

}

export default wrapper(ViewDataSourceQueues)
