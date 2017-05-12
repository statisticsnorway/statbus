import React from 'react'
import { func, shape, arrayOf, number, string } from 'prop-types'
import { Grid, Input, Dropdown, Button, Modal, Segment, List } from 'semantic-ui-react'
import Dropzone from 'react-dropzone'

import { wrapper } from 'helpers/locale'
import styles from './styles.pcss'

class Upload extends React.Component {

  static propTypes = {
    localize: func.isRequired,
    fetchData: func.isRequired,
    uploadFile: func.isRequired,
    dataSources: arrayOf(shape({
      id: number.isRequired,
      name: string.isRequired,
    })),
  }

  static defaultProps = {
    dataSources: [],
  }

  state = {
    description: '',
    dataSourceId: undefined,
    accepted: [],
    rejected: [],
    modalChoose: false,
    busy: false,
  }

  componentDidMount() {
    this.props.fetchData()
  }

  onDrop = (accepted, rejected) => {
    this.setState({
      accepted,
      rejected,
      dropzoneActive: false,
    })
  }

  handleSubmit = () => {
    this.setState({ modalChoose: false, busy: true })
    const { accepted: files, dataSourceId, description } = this.state
    const formData = new FormData()
    files.forEach((x) => { formData.append('datafile', x, x.name) })
    formData.append('DataSourceId', dataSourceId)
    formData.append('Description', description)
    this.props.uploadFile(formData, () => {
      this.setState({ accepted: [], rejected: [], busy: false })
    })
  }

  selectDataSource = (e, data) => {
    this.setState({ dataSourceId: data.value })
  }

  writeDescription = (e, data) => {
    this.setState({ description: data.value })
  }

  dsModalToggle = () => {
    this.setState({ modalChoose: !this.state.modalChoose })
  }

  dsDropdown = options => (<Dropdown
    fluid
    placeholder={this.props.localize('SelectDataSource')}
    value={this.state.dataSourceId}
    selection
    options={options}
    onChange={this.selectDataSource}
  />)

  descriptionDropDown = () => (<Input
    fluid
    value={this.state.description}
    placeholder={this.props.localize('EnterDescription')}
    onChange={this.writeDescription}
  />
  )
  fileInfo() {
    if (this.state.accepted.length === 0) {
      return (<p>{this.props.localize('DropZoneLabel')}</p>)
    }
    return (
      <List>
        <List.Header>{this.props.localize('NextFilesReadyForUpload')}</List.Header>
        {this.state.accepted.map(x =>
            (<List.Item key={x.name} className={styles['dz-list']}>
              <List.Icon name="file text outline" />
              <List.Content>
                <List.Header>{x.name}</List.Header>
                <List.Description>{x.type} {Math.ceil(x.size / 1024)}Kb</List.Description>
              </List.Content>
            </List.Item>))}
      </List>)
  }
  render() {
    const { localize, dataSources } = this.props
    const { accepted: files, rejected, dataSourceId, modalChoose, busy } = this.state
    const options = dataSources.map(x => ({ text: x.name, value: x.id }))
    let dropzoneRef
    const checks = (files.length > 0 && dataSourceId !== undefined)
    return (
      <Segment loading={busy}>
        <Grid>
          <Grid.Row columns={2}>
            <Grid.Column width={6}>
              {this.dsDropdown(options)}
            </Grid.Column>
            <Grid.Column width={10}>
              {this.descriptionDropDown()}
            </Grid.Column>
          </Grid.Row>
          <Grid.Row columns={1}>
            <Grid.Column>
              <Dropzone
                className={styles['dz-container']}
                multiple={false}
                ref={(node) => { dropzoneRef = node }}
                accept="text/csv, text/xml, text/plain"
                onDrop={this.onDrop}
              >
                {this.fileInfo()}
              </Dropzone>
            </Grid.Column>
          </Grid.Row>
          <Grid.Row>
            <Grid.Column>
              <Button
                icon="upload"
                color={checks ? 'green' : 'blue'}
                onClick={checks ?
              this.handleSubmit : dataSourceId === undefined ?
              this.dsModalToggle : () => { dropzoneRef.open() }}
                content={localize('UpLoad')}
              />
            </Grid.Column>
          </Grid.Row>
          <Modal
            open={modalChoose}
            size="small"
          >
            <Modal.Header>
              {localize('SelectDataSource')}
            </Modal.Header>
            <Modal.Content>
              <Grid>
                <Grid.Row columns={1}>
                  <Grid.Column>
                    {this.dsDropdown(options)}
                  </Grid.Column>
                </Grid.Row>
                <Grid.Row columns={1}>
                  <Grid.Column>
                    {this.descriptionDropDown()}
                  </Grid.Column>
                </Grid.Row>
              </Grid>
            </Modal.Content>
            <Modal.Actions>
              <Button negative content={localize('ButtonCancel')} onClick={this.dsModalToggle} />
              <Button
                positive
                icon={checks ? 'upload' : 'checkmark'}
                labelPosition="right"
                content={localize(checks ? 'UpLoad' : 'Ok')}
                onClick={checks ?
                this.handleSubmit :
                dataSourceId !== undefined ?
                () => { dropzoneRef.open() } :
                this.dsModalToggle}
              />
            </Modal.Actions>
          </Modal>
          <Modal
            open={rejected.length > 0}
            size="small"
          >
            <Modal.Header>
              {localize('UnsuportedFileFormat')}
            </Modal.Header>
            <Modal.Content>
              {localize('OnlySupportedFormatsAllowed')}: CSV, TXT, XML
              <br />
              {localize('NextFilesWillNotBeUploaded')}
              <ui>
                {rejected.map(x => (<li key={x.name}>{x.name}</li>))}
              </ui>
            </Modal.Content>
            <Modal.Actions>
              <Button content={localize('Ok')} negative onClick={() => this.setState({ rejected: [] })} />
            </Modal.Actions>
          </Modal>
        </Grid>
      </Segment>
    )
  }
}

export default wrapper(Upload)
