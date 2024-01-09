import React from 'react'
import { arrayOf, shape, func, string, number, oneOfType } from 'prop-types'
import { Link } from 'react-router'
import * as R from 'ramda'
import { Button, Table, Segment, Confirm, Modal, Header } from 'semantic-ui-react'

import { checkSystemFunction as sF } from '/helpers/config'
import Paginate from '/components/Paginate'
import SearchForm from './SearchForm.jsx'
import ListItem from './ListItem.jsx'

class List extends React.Component {
  static propTypes = {
    formData: shape({
      wildcard: string,
      statUnitType: oneOfType([number, string]),
      priority: oneOfType([number, string]),
      allowedOperations: oneOfType([number, string]),
    }).isRequired,
    query: shape({}).isRequired,
    dataSources: arrayOf(shape({
      id: number.isRequired,
      name: string.isRequired,
    })),
    totalCount: oneOfType([string, number]).isRequired,
    onSubmit: func.isRequired,
    onChange: func.isRequired,
    onItemDelete: func.isRequired,
    localize: func.isRequired,
    fetchData: func.isRequired,
    clear: func.isRequired,
    errors: shape({
      message: string.isRequired,
    }),
    fetchError: func.isRequired,
  }

  static defaultProps = {
    dataSources: [],
    errors: undefined,
  }

  state = {
    selectedDataSource: undefined,
  }

  componentDidMount() {
    this.props.fetchData(this.props.query)
  }

  componentWillReceiveProps(nextProps) {
    if (!R.equals(nextProps.query, this.props.query)) {
      nextProps.fetchData(nextProps.query)
    }
  }

  componentWillUnmount() {
    this.props.clear()
  }

  displayConfirm = id => () => {
    this.setState({ selectedDataSource: id })
  }

  handleConfirm = () => {
    const selectedId = this.state.selectedDataSource
    this.setState({ selectedDataSource: undefined }, () => this.props.onItemDelete(selectedId))
  }

  handleCancel = () => {
    this.setState({ selectedDataSource: undefined })
  }

  renderConfirm() {
    const { dataSources, localize } = this.props
    const { name } = dataSources.find(ds => ds.id === this.state.selectedDataSource)
    return (
      <Confirm
        onConfirm={this.handleConfirm}
        onCancel={this.handleCancel}
        header={`${localize('AreYouSure')}`}
        content={`${localize('DeleteDataSourceMessage')} "${name}"?`}
        open
      />
    )
  }

  render() {
    const {
      formData,
      dataSources,
      totalCount,
      onSubmit,
      onChange,
      localize,
      errors,
      fetchError,
    } = this.props
    const canEdit = sF('DataSourcesEdit')
    const canDelete = sF('DataSourcesDelete')
    return (
      <div>
        <h2>{localize('DataSources')}</h2>
        <Button
          as={Link}
          to="/datasources/create"
          content={localize('CreateDataSource')}
          icon="add square"
          size="medium"
          color="green"
        />
        {this.state.selectedDataSource !== undefined && this.renderConfirm()}
        <Segment>
          <SearchForm
            formData={formData}
            onSubmit={onSubmit}
            onChange={onChange}
            localize={localize}
          />
          <br />
          <Paginate totalCount={Number(totalCount)}>
            <Table selectable size="small" className="wrap-content" fixed>
              <Table.Header>
                <Table.Row>
                  <Table.HeaderCell content={localize('Name')} />
                  <Table.HeaderCell content={localize('Description')} />
                  <Table.HeaderCell content={localize('Priority')} />
                  <Table.HeaderCell content={localize('AllowedOperations')} />
                  {canDelete && <Table.HeaderCell />}
                </Table.Row>
              </Table.Header>
              <Table.Body>
                {dataSources.map(ds => (
                  <ListItem
                    key={ds.id}
                    canEdit={canEdit}
                    canDelete={canDelete}
                    onDelete={canDelete ? this.displayConfirm(ds.id) : R.identity}
                    localize={localize}
                    {...ds}
                  />
                ))}
              </Table.Body>
            </Table>
          </Paginate>
        </Segment>
        {errors && (
          <Modal open size="mini">
            <Header content={localize('CantDeleteDatasourceTemp')} />
            <Modal.Content>{localize(errors.message)}</Modal.Content>
            <Modal.Actions>
              <Button color="blue" onClick={() => fetchError()}>
                {localize('Ok')}
              </Button>
            </Modal.Actions>
          </Modal>
        )}
      </div>
    )
  }
}

export default List
